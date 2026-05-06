#!/usr/bin/env bash
set -euo pipefail

WATCH="/srv/media/music/incoming"
LIBRARY="/srv/media/music/library"
DOUJIN="/srv/media/music/doujin"
UNSORTED="/srv/media/music/unsorted"
LOG="/srv/media/music/classify.log"

mkdir -p "$WATCH" "$LIBRARY" "$DOUJIN" "$UNSORTED"

is_doujin_name() {
  local name="$1"

  echo "$name" | grep -Eiq \
    'RJ[0-9]+|DLsite|ASMR|KU100|バイノーラル|耳かき|催眠|処女|CV\.|サークル|音声作品'
}

is_doujin_contents() {
  local dir="$1"

  # テキスト系や典型トラック名が多い場合
  find "$dir" -maxdepth 2 -type f | grep -Eiq \
    'readme|Track ?0?[0-9]|導入|本編|耳かき|フリートーク|おまけ|CV\.|ジャケット|パッケージ'
}

move_safely() {
  local src="$1"
  local dest_dir="$2"
  local name
  name="$(basename "$src")"
  local dest="$dest_dir/$name"

  if [ -e "$dest" ]; then
    local i=1
    while [ -e "$dest_dir/${name}_$i" ]; do
      i=$((i+1))
    done
    dest="$dest_dir/${name}_$i"
  fi

  mv "$src" "$dest"
  echo "$(date '+%F %T') moved: $src -> $dest" >> "$LOG"
}

classify_one() {
  local path="$1"
  [ -e "$path" ] || return 0

  local base
  base="$(basename "$path")"

  if is_doujin_name "$base"; then
    move_safely "$path" "$DOUJIN"
    return 0
  fi

  if [ -d "$path" ] && is_doujin_contents "$path"; then
    move_safely "$path" "$DOUJIN"
    return 0
  fi

  # 音楽らしい拡張子中心なら library
  if find "$path" -type f 2>/dev/null | grep -Eiq '\.(mp3|flac|m4a|aac|ogg|wav)$'; then
    move_safely "$path" "$LIBRARY"
    return 0
  fi

  move_safely "$path" "$UNSORTED"
}

# 起動時の既存処理
find "$WATCH" -mindepth 1 -maxdepth 1 \( -type d -o -type f \) -print0 | while IFS= read -r -d '' item; do
  classify_one "$item"
done

# 監視
inotifywait -mr -e close_write,moved_to,create --format '%w%f' "$WATCH" | while IFS= read -r item; do
  # 直下の項目だけ対象
  parent="$(dirname "$item")"
  if [ "$parent" = "$WATCH" ]; then
    classify_one "$item"
  fi
done
