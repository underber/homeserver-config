#!/usr/bin/env bash
set -euo pipefail

WATCH="/srv/media/manga/incoming"
DEST="/srv/media/manga/library"
LOG="/srv/media/manga/zip2cbz.log"

mkdir -p "$WATCH" "$DEST"

wait_until_stable() {
  local file="$1"
  local old_size=-1 new_size=0
  while [ -f "$file" ]; do
    new_size=$(stat -c %s "$file" 2>/dev/null || echo 0)
    [ "$new_size" -eq "$old_size" ] && [ "$new_size" -gt 0 ] && return 0
    old_size="$new_size"
    sleep 2
  done
  return 1
}

# Return the best-matching existing series directory for a title, or empty string.
# Two entries match when their common prefix covers >= 80% of the shorter name
# (minimum 3 chars). Longest common prefix wins among multiple candidates.
find_series_dir() {
  python3 - "$1" "$DEST" <<'PYEOF'
import os, sys

title = sys.argv[1]
dest  = sys.argv[2]
best_path  = ""
best_score = 0

for name in os.listdir(dest):
    path = os.path.join(dest, name)
    if not os.path.isdir(path):
        continue
    cp = 0
    for a, b in zip(title, name):
        if a == b:
            cp += 1
        else:
            break
    min_len = min(len(title), len(name))
    if cp >= 3 and cp * 10 >= min_len * 8 and cp > best_score:
        best_path  = path
        best_score = cp

print(best_path, end="")
PYEOF
}

convert_one() {
  local file="$1"
  [ -f "$file" ] || return 0

  local ext
  ext="$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    zip|cbz) ;;
    *) return 0 ;;
  esac

  wait_until_stable "$file" || return 1

  local title cbz_name target_dir out
  title="$(basename "$file")"
  title="${title%.*}"
  cbz_name="${title}.cbz"

  target_dir="$(find_series_dir "$title")"
  if [ -z "$target_dir" ]; then
    target_dir="$DEST/$title"
    mkdir -p "$target_dir"
  fi

  out="$target_dir/$cbz_name"
  if [ -e "$out" ]; then
    local i=1
    while [ -e "$target_dir/${title}_${i}.cbz" ]; do
      i=$((i+1))
    done
    out="$target_dir/${title}_${i}.cbz"
  fi

  mv "$file" "$out"
  echo "$(date '+%F %T') moved: $file -> $out" >> "$LOG"
}

export -f wait_until_stable find_series_dir convert_one
export DEST LOG

find "$WATCH" -maxdepth 1 -type f \( -iname '*.zip' -o -iname '*.cbz' \) -print0 | while IFS= read -r -d '' f; do
  convert_one "$f"
done

inotifywait -m -e close_write,moved_to --format '%w%f' "$WATCH" | while IFS= read -r f; do
  convert_one "$f"
done
