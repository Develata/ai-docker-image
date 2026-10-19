#!/usr/bin/env bash
set -euo pipefail
umask 022

# Explicit build-time/manual command. Nothing invokes this at container startup.
root=/opt/agent-tools
mkdir -p "$root"
exec 9>"$root/.update.lock"
flock -n 9 || { echo "Another tool installation is running." >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

case "$(dpkg --print-architecture)" in
  amd64) cpu=x86_64; bun_cpu=x64; claude_platform=linux-x64 ;;
  arm64) cpu=aarch64; bun_cpu=aarch64; claude_platform=linux-arm64 ;;
  *) echo "Only linux/amd64 and linux/arm64 are supported." >&2; exit 1 ;;
esac

fetch() {
  curl --fail --show-error --silent --location --retry 3 \
    --connect-timeout 20 --max-time 300 --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$1" -o "$2"
}
sha() { sha256sum "$1" | awk '{print $1}'; }
verify() {
  [[ "$2" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo "Missing/invalid upstream SHA-256." >&2; exit 1;
  }
  printf '%s  %s\n' "$2" "$1" | sha256sum --check --status
}
latest_release() {
  fetch "https://api.github.com/repos/$1/releases/latest" "$2"
  jq -e '.draft == false and .prerelease == false' "$2" >/dev/null
}
github_asset() {
  local metadata="$1" name="$2" destination="$3"
  asset_url="$(jq -er --arg n "$name" \
    '[.assets[] | select(.name == $n)] | if length == 1 then .[0].browser_download_url else error("asset missing or ambiguous") end' "$metadata")"
  asset_digest="$(jq -er --arg n "$name" \
    '.assets[] | select(.name == $n) | .digest | select(startswith("sha256:")) | ltrimstr("sha256:")' "$metadata")"
  [[ "$asset_url" == https://github.com/*/releases/download/* ]] || exit 1
  fetch "$asset_url" "$destination"
  verify "$destination" "$asset_digest"
}
publish() {
  local name="$1" version="$2" stage="$3" source="$4" digest="$5" executable="$6"
  local base="$root/$name" release
  mkdir -p "$base/releases"
  [[ ! -e "$base/current" || -L "$base/current" ]] || {
    echo "$base/current is not a symlink; refusing to replace it." >&2; exit 1;
  }
  release="$(mktemp -d "$base/releases/$version.XXXXXX")"
  cp -a "$stage/." "$release/"
  chmod 755 "$release"
  jq -n --arg tool "$name" --arg version "$version" --arg source "$source" \
    --arg sourceSha256 "$digest" --arg executableSha256 "$(sha "$release/$executable")" \
    --arg release "$release" \
    '{tool:$tool, version:$version, source:$source, sourceSha256:$sourceSha256,
      executableSha256:$executableSha256, release:$release, installedAt:(now|todate)}' \
    > "$release/installed.json"
  ln -s "releases/${release##*/}" "$base/.current.$$"
  mv -Tf "$base/.current.$$" "$base/current"
  cp "$release/installed.json" "$base/.installed.$$"
  mv -f "$base/.installed.$$" "$base/installed.json"
  echo "$name $version installed. Old releases remain until container recreation."
}

install_claude() {
  local work="$tmp/claude" version native manifest checksum fingerprint
  mkdir -p "$work/home" "$work/stage" "$work/gpg"
  chmod 700 "$work/gpg"
  fetch https://claude.ai/install.sh "$work/install.sh"
  # Official native installer; isolate all installer state from persistent HOME.
  HOME="$work/home" CLAUDE_CONFIG_DIR="$work/home/.claude" \
    DISABLE_AUTOUPDATER=1 bash "$work/install.sh" stable
  native="$(readlink -f "$work/home/.local/bin/claude")"
  [[ -f "$native" && "$native" == "$work/home/"* ]] || exit 1
  version="$(HOME="$work/home" "$native" --version | awk 'NR == 1 {print $1}')"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1

  # Check the installed native binary against Anthropic's signed manifest.
  fetch https://downloads.claude.ai/keys/claude-code.asc "$work/key.asc"
  fingerprint="$(gpg --batch --homedir "$work/gpg" --with-colons --show-keys "$work/key.asc" \
    | awk -F: '$1 == "fpr" {print $10; exit}')"
  [[ "$fingerprint" == 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE ]] || {
    echo "Claude signing key changed; review before updating." >&2; exit 1;
  }
  gpg --batch --homedir "$work/gpg" --import "$work/key.asc"
  manifest="https://downloads.claude.ai/claude-code-releases/$version/manifest.json"
  fetch "$manifest" "$work/manifest.json"
  fetch "$manifest.sig" "$work/manifest.json.sig"
  gpg --batch --homedir "$work/gpg" --verify "$work/manifest.json.sig" "$work/manifest.json"
  checksum="$(jq -er --arg p "$claude_platform" '.platforms[$p].checksum' "$work/manifest.json")"
  verify "$native" "$checksum"
  install -m 755 "$native" "$work/stage/claude"
  cp "$work/manifest.json" "$work/manifest.json.sig" "$work/stage/"
  printf '%s  install.sh\n' "$(sha "$work/install.sh")" > "$work/stage/installer.sha256"
  publish claude "$version" "$work/stage" "$manifest" "$(sha "$work/manifest.json")" claude
}

install_codex() {
  local work="$tmp/codex" version target asset reported
  mkdir -p "$work/stage"
  latest_release openai/codex "$work/release.json"

  version="$(jq -er '.tag_name' "$work/release.json")"
  [[ "$version" =~ ^rust-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Unexpected Codex stable-release tag: $version" >&2
    exit 1
  }
  version="${version#rust-v}"
  target="$cpu-unknown-linux-musl"
  asset="codex-package-$target.tar.gz"

  github_asset "$work/release.json" "$asset" "$work/package.tar.gz"
  tar -xzf "$work/package.tar.gz" --no-same-owner -C "$work/stage"

  if ! jq -e --arg v "$version" --arg t "$target" '
      .layoutVersion == 1 and
      .version == $v and
      .target == $t and
      .variant == "codex" and
      .entrypoint == "bin/codex" and
      .resourcesDir == "codex-resources" and
      .pathDir == "codex-path"
    ' "$work/stage/codex-package.json" >/dev/null; then
    echo "Unsupported Codex package layout; review the upstream release before updating." >&2
    exit 1
  fi

  for binary in bin/codex bin/codex-code-mode-host codex-resources/bwrap codex-path/rg; do
    if [[ ! -f "$work/stage/$binary" || ! -x "$work/stage/$binary" ]]; then
      echo "Missing or non-executable Codex package component: $binary" >&2
      exit 1
    fi
  done

  if ! reported="$("$work/stage/bin/codex" --no-daemon --version)"; then
    echo "Codex cannot run with the image's required --no-daemon option." >&2
    exit 1
  fi
  [[ "$(awk '{print $2}' <<< "$reported")" == "$version" ]] || {
    echo "Codex executable version does not match its release metadata." >&2
    exit 1
  }

  (cd "$work/stage"; sha256sum bin/codex bin/codex-code-mode-host codex-resources/bwrap codex-path/rg) \
    > "$work/stage/installed-files.sha256"
  publish codex "$version" "$work/stage" "$asset_url" "$asset_digest" bin/codex
}

install_bun() {
  local work="$tmp/bun" version asset
  mkdir -p "$work/stage"
  latest_release oven-sh/bun "$work/release.json"
  version="$(jq -er '.tag_name' "$work/release.json")"
  [[ "$version" =~ ^bun-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
  version="${version#bun-v}"
  asset="bun-linux-$bun_cpu.zip"
  github_asset "$work/release.json" "$asset" "$work/bun.zip"
  unzip -q "$work/bun.zip" -d "$work/unpacked"
  install -m 755 "$work/unpacked/bun-linux-$bun_cpu/bun" "$work/stage/bun"
  [[ "$("$work/stage/bun" --version)" == "$version" ]] || exit 1
  "$work/stage/bun" --revision > "$work/stage/revision.txt"
  publish bun "$version" "$work/stage" "$asset_url" "$asset_digest" bun
}

case "${1:-}" in
  all) install_claude; install_codex; install_bun ;;
  claude) install_claude ;;
  codex) install_codex ;;
  bun) install_bun ;;
  *) echo "Usage: agent-tools-update {all|claude|codex|bun}" >&2; exit 2 ;;
esac
