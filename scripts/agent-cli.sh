#!/usr/bin/env bash
set -euo pipefail
case "$(basename "$0")" in
  claude)
    export DISABLE_AUTOUPDATER=1
    exec /opt/agent-tools/claude/current/claude "$@"
    ;;
  codex)
    # Embedded/foreground operation, even if a daemon already exists.
    exec /opt/agent-tools/codex/current/bin/codex \
      --no-daemon -c check_for_update_on_startup=false "$@"
    ;;
  bun)
    exec /opt/agent-tools/bun/current/bun "$@"
    ;;
  bunx)
    exec /opt/agent-tools/bun/current/bun x "$@"
    ;;
  *) echo "Invoke this launcher as claude, codex, bun, or bunx." >&2; exit 2 ;;
esac
