#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ "$(id -u)" != 0 ]] || { echo "Refusing to run the agent as root." >&2; exit 1; }
[[ "$HOME" == /home/agent && "$CODEX_HOME" == /home/agent/.codex ]] || {
  echo "This image expects HOME=/home/agent and CODEX_HOME=/home/agent/.codex." >&2
  exit 1
}
[[ -w "$HOME" ]] || {
  echo "Home volume is not writable. Check image UID/GID and volume ownership." >&2
  exit 1
}
mkdir -p "$CODEX_HOME" "$HOME/.claude" "$HOME/.bun/bin"
[[ -e "$HOME/.claude.json" ]] || printf '{}\n' > "$HOME/.claude.json"

if [[ "${1:-}" == sshd ]]; then
  shift
  [[ -s /run/agent-authorized-keys && -r /run/agent-authorized-keys ]] || {
    echo "Mount a readable, nonempty public authorized_keys file." >&2
    exit 1
  }
  mkdir -p "$HOME/.ssh" "$HOME/.ssh-host"
  chmod 700 "$HOME/.ssh" "$HOME/.ssh-host"
  install -m 600 /run/agent-authorized-keys "$HOME/.ssh/authorized_keys"
  if [[ ! -e "$HOME/.ssh-host/ssh_host_ed25519_key" ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh-host/ssh_host_ed25519_key"
  fi
  echo "SSH host key fingerprint:"
  ssh-keygen -lf "$HOME/.ssh-host/ssh_host_ed25519_key.pub"
  /usr/sbin/sshd -t -f /etc/ssh/agent_sshd_config
  exec /usr/sbin/sshd -D -e -f /etc/ssh/agent_sshd_config "$@"
fi
exec "$@"
