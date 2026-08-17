#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROL="$ROOT/scripts/github-homeserver-control.sh"

bash -n "$CONTROL"

if "$CONTROL" arbitrary-command >/dev/null 2>&1; then
  echo "FAIL: an unknown action was accepted" >&2
  exit 1
fi

echo "GitHub homeserver control allowlist test passed."
