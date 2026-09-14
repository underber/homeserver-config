#!/usr/bin/env bash
set -euo pipefail
STATE_DIR=/run/media-library-watch
PENDING_FILE=$STATE_DIR/pending
LOCK_FILE=$STATE_DIR/debounce.lock
DEBOUNCE_SECONDS=${DEBOUNCE_SECONDS:-60}
WATCH_PATHS=(/srv/media/movies /srv/media/tv /srv/media/music /srv/media/audiobooks /srv/media/podcasts /srv/media/manga/library /srv/media/comics/library)
install -d -m 0755 "$STATE_DIR"
existing_paths=()
for path in "${WATCH_PATHS[@]}"; do [[ -d "$path" ]] && existing_paths+=("$path"); done
((${#existing_paths[@]})) || { echo "no media paths available" >&2; exit 1; }
echo "watching ${existing_paths[*]}"
inotifywait -m -r -q -e create,moved_to,close_write --format '%e|%w%f' "${existing_paths[@]}" |
while IFS= read -r event; do
  touch "$PENDING_FILE"
  (
    flock -n 9 || exit 0
    while :; do
      before=$(stat -c %Y "$PENDING_FILE")
      sleep "$DEBOUNCE_SECONDS"
      after=$(stat -c %Y "$PENDING_FILE")
      [[ "$before" == "$after" ]] && break
    done
    echo "media changes settled; requesting library refresh"
    systemctl start --no-block media-library-refresh.service
  ) 9>"$LOCK_FILE" &
done
