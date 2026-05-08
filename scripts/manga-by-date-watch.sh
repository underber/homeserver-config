#!/usr/bin/env bash
# Watch the manga library and rebuild by-date symlinks when files change.
# Bursts of events are coalesced (waits for 5s of quiet before rebuilding).

set -euo pipefail

LIBRARY="/srv/media/manga/library"
SCRIPT="/srv/scripts/manga-by-date.sh"

# Initial build so by-date is in sync at startup.
"$SCRIPT"

inotifywait -m -r -q \
    -e create,moved_to,delete,moved_from,close_write \
    --format '%e' "$LIBRARY" |
while read -r _; do
    while read -r -t 5 _; do :; done
    "$SCRIPT"
done
