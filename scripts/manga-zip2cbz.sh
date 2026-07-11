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
# Logic: normalize the title (strip leading/trailing bracketed tags and trailing
# volume/edition markers), then compare against the normalized name of every
# existing series directory. Two titles are considered the same series if:
#   1. their normalized forms are identical, OR
#   2. one is a prefix of the other AND the leftover tail is only separators /
#      volume markers (so "タイトル" ↔ "タイトル 2" matches, but "COMIC 快楽天"
#      ↔ "COMIC 快楽天ビースト" does not), OR
#   3. SequenceMatcher.ratio on the normalized forms is >= 0.90.
# When multiple existing directories pass, the highest score wins.
find_series_dir() {
  python3 - "$1" "$DEST" <<'PYEOF'
import os, re, sys
from difflib import SequenceMatcher

THRESH = 0.90
title_raw = sys.argv[1]
dest = sys.argv[2]

BRACKET_PAIRS = [("[", "]"), ("(", ")"), ("（", "）"), ("【", "】"),
                 ("〔", "〕"), ("「", "」"), ("『", "』"), ("<", ">"), ("〈", "〉")]

VOL_TAIL = (
    r"(?i)(?:[\s\-_.,。、~〜~+＋&]+)"
    r"(?:第\s*\d+\s*[巻話章部回]|vol\.?\s*\d+|volume\s*\d+|ch\.?\s*\d+|"
    r"chapter\s*\d+|\#\s*\d+|\d+(?:\s*[+＋&]\s*\d+)*|"
    r"[①-⑳]+|[Ⅰ-Ⅻ]+|[一二三四五六七八九十]{1,3}|"
    r"上|下|前編|後編|中編|総集編|完全版|特装版|デジタル版|"
    r"デジタル特装版|DL版|電子書籍版|新装版|愛蔵版|R18版|無修正版)"
    r"\s*$"
)

TAIL_NOISE = (
    r"(?i)[\s\-_.,。、~〜~+＋&]+|第\s*\d+\s*[巻話章部回]|"
    r"vol\.?\s*\d+|volume\s*\d+|ch\.?\s*\d+|chapter\s*\d+|\#\s*\d+|"
    r"\d+|[①-⑳]+|[Ⅰ-Ⅻ]+|[一二三四五六七八九十]{1,3}|"
    r"上|下|前編|後編|中編|総集編|完全版|特装版|デジタル版|"
    r"デジタル特装版|DL版|電子書籍版|新装版|愛蔵版|R18版|無修正版"
)

def strip_brackets(s, leading=True):
    changed = True
    while changed:
        changed = False
        s = s.lstrip() if leading else s.rstrip()
        for L, R in BRACKET_PAIRS:
            if leading and s.startswith(L):
                i = s.find(R)
                if i != -1:
                    s = s[i + len(R):]
                    changed = True
                    break
            elif not leading and s.endswith(R):
                i = s.rfind(L)
                if i != -1:
                    s = s[:i]
                    changed = True
                    break
    return s

def normalize(t):
    s = t.translate(str.maketrans("０１２３４５６７８９", "0123456789"))
    s = strip_brackets(s, leading=True)
    s = strip_brackets(s, leading=False)
    while True:
        m = re.search(VOL_TAIL, s)
        if not m:
            break
        s = s[:m.start()].rstrip()
    s2 = re.sub(r"\d+\s*$", "", s)
    if s2 != s and len(s2.strip()) >= 3:
        s = s2.rstrip()
    return re.sub(r"\s+", " ", s).strip()

def same_series(a, b):
    if not a or not b or a == b:
        return (1.0 if a == b and a else 0.0)
    short, long = (a, b) if len(a) <= len(b) else (b, a)
    if long.startswith(short):
        tail = long[len(short):]
        cleaned = re.sub(TAIL_NOISE, "", tail).strip()
        if cleaned == "":
            return 0.99
        return 0.0
    r = SequenceMatcher(None, a, b).ratio()
    return r if r >= THRESH else 0.0

norm_title = normalize(title_raw)
best_path = ""
best_score = 0.0
if len(norm_title) >= 3:
    for name in os.listdir(dest):
        path = os.path.join(dest, name)
        if not os.path.isdir(path):
            continue
        norm_name = normalize(name)
        if len(norm_name) < 3:
            continue
        score = same_series(norm_title, norm_name)
        if score > best_score:
            best_score = score
            best_path = path

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
