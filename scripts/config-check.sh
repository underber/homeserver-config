#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
bash -n "$repo"/*.sh "$repo"/scripts/*.sh
python3 -m py_compile "$repo"/scripts/*.py "$repo"/web/start/*.py
for compose in "$repo"/docker/*/docker-compose.yml; do docker compose -f "$compose" config --quiet; done
caddy validate --config "$repo/caddy/Caddyfile" --adapter caddyfile
echo "Configuration checks passed."
