#!/usr/bin/env bash
set -euo pipefail

# Fork-time extension point, run once as root while building.
# No runtime package installation or background updater is started here.
# Add only tools your projects need. Keep a Lean toolchain/elan prefix under
# /opt, not /home/agent, so persisted state cannot hide a rebuilt toolchain.
# Record resolved versions and verified download hashes under
# /usr/local/share/agent-image/ for every additional downloaded tool.
# Never put tokens/passwords in this file, ARG, ENV, URLs, or image layers.
# If a build really needs a secret, use a separately reviewed BuildKit secret
# mount and ensure neither the output nor logs retain it.
:
