#!/usr/bin/env bash
set -euo pipefail

WATCH="/srv/downloads"
MUSIC="/srv/incoming/music"
MANGA_IN="/srv/incoming/manga"
LOG="/srv/media/media-sort.log"

mkdir -p "$WATCH" "$MUSIC" "$MANGA_IN"

wait_until_stable() {
  local file="$1"
  local old_size=-1
  local new_size=0

  while [ -f "$file" ]; do
    new_size=$(stat -c %s "$file" 2>/dev/null || echo 0)
    if [ "$new_size" -eq "$old_size" ] && [ "$new_size" -gt 0 ]; then
      return 0
    fi
    old_size="$new_size"
    sleep 2
  done
  return 1
}

move_one() {
  local file="$1"
  [ -f "$file" ] || return 0

  wait_until_stable "$file" || return 1

  local name ext dest
  name="$(basename "$file")"
  ext="${name##*.}"
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  case "$ext" in
    mp3|flac|m4a|wav|aac|ogg|opus)
      dest="$MUSIC/$name"
      ;;
    zip|cbz)
      dest="$MANGA_IN/$name"
      ;;
    *)
      echo "$(date '+%F %T') skip: $name" >> "$LOG"
      return 0
      ;;
  esac

  if [ -e "$dest" ]; then
    local base stem i
    base="${name%.*}"
    i=1
    while [ -e "${dest%/*}/${base}_$i.${ext}" ]; do
      i=$((i+1))
    done
    dest="${dest%/*}/${base}_$i.${ext}"
  fi

  mv "$file" "$dest"
  echo "$(date '+%F %T') moved: $file -> $dest" >> "$LOG"
}

# A single failed move_one must never tear down the watcher loop.
# Calling in a `|| ...` context also disables `set -e` inside the function,
# so a transient stat/mv failure on a vanishing temp file is non-fatal.
find "$WATCH" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' f; do
  move_one "$f" || echo "$(date '+%F %T') error: $f" >> "$LOG"
done

inotifywait -mr -e close_write,create,moved_to --format '%w%f' "$WATCH" | while IFS= read -r f; do
  move_one "$f" || echo "$(date '+%F %T') error: $f" >> "$LOG"
done
