#!/usr/bin/env bash
set -euo pipefail

WATCH="/srv/shares/uploads"
MUSIC="/srv/media/music/incoming"
MANGA_IN="/srv/media/manga/incoming"
LOG="/srv/shares/uploads/media-sort.log"

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
    mp3|flac|m4a|wav|aac|ogg)
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

find "$WATCH" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' f; do
  move_one "$f"
done

inotifywait -mr -e close_write,create,moved_to --format '%w%f' "$WATCH" | while IFS= read -r f; do
  move_one "$f"
done
