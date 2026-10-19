#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# --no-cache is intentional: 'latest' endpoints otherwise reuse stale layers.
docker compose build --pull --no-cache agent
image="$(docker compose config --images)"
docker image inspect "$image" --format 'Built image ID: {{.Id}}'
