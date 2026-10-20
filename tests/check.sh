#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

for script in scripts/*.sh custom/install.sh config/agent-profile.sh tests/check.sh; do
  bash -n "$script"
done
docker compose config --quiet

docker compose run --rm --no-deps \
  -e EXPECT_NO_NODE="${EXPECT_NO_NODE:-1}" \
  agent bash -euo pipefail -c '
  test "$(id -u)" != 0

  if command -v sudo >/dev/null 2>&1; then
    echo "sudo must not be installed." >&2
    exit 1
  fi

  if [[ "$EXPECT_NO_NODE" == 1 ]]; then
    for name in node npm; do
      if command -v "$name" >/dev/null 2>&1; then
        echo "Unexpected default dependency: $name" >&2
        exit 1
      fi
    done
  fi

  claude --version
  codex --version
  bun --version
  tmux -V
  jq -e ".tools | length == 3" /usr/local/share/agent-image/build-manifest.json
  test -x /opt/agent-tools/codex/current/codex-resources/bwrap
  test -x /opt/agent-tools/codex/current/codex-path/rg
  test -w "$HOME/.bun/bin"
  test -w "$HOME/.claude.json"
'
