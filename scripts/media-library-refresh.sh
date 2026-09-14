#!/usr/bin/env bash
set -euo pipefail
JELLYFIN_URL=${JELLYFIN_URL:-http://127.0.0.1:8096}
KOMGA_URL=${KOMGA_URL:-http://127.0.0.1:25600}
KAVITA_URL=${KAVITA_URL:-http://127.0.0.1:5001}
failures=()
if curl --fail --silent --show-error --max-time 20 -X POST -H "Authorization: MediaBrowser Token=\"$JELLYFIN_API_KEY\"" "${JELLYFIN_URL%/}/Library/Refresh" >/dev/null; then
  echo "Jellyfin library refresh queued"
else failures+=(Jellyfin); fi
if response=$(curl --fail --silent --show-error --max-time 20 -H "X-API-Key: $KOMGA_API_KEY" "${KOMGA_URL%/}/api/v1/libraries"); then
  while IFS= read -r library_id; do
    [[ -n "$library_id" ]] || continue
    if curl --fail --silent --show-error --max-time 20 -X POST -H "X-API-Key: $KOMGA_API_KEY" "${KOMGA_URL%/}/api/v1/libraries/${library_id}/scan" >/dev/null; then
      echo "Komga library refresh queued: $library_id"
    else failures+=("Komga:$library_id"); fi
  done < <(python3 -c 'import json,sys
value=json.load(sys.stdin)
items=value.get("content", []) if isinstance(value, dict) else value
for item in items:
    if item.get("id"): print(item["id"])' <<<"$response")
else failures+=(Komga); fi
if curl --fail --silent --show-error --max-time 20 -X POST -H "x-api-key: $KAVITA_API_KEY" "${KAVITA_URL%/}/api/Library/scan-all" >/dev/null; then
  echo "Kavita library refresh queued"
else failures+=(Kavita); fi
if ((${#failures[@]})); then
  printf 'library refresh failed: %s\n' "${failures[*]}" >&2
  exit 1
fi
