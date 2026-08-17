#!/bin/bash

WATCH="/srv/incoming/music"
DEST="/srv/media/music/classify"
BEET_LOG="$HOME/.config/beets/import.log"

mkdir -p "$WATCH" "$DEST"

wait_until_stable() {
    local file="$1"
    local old_size=-1
    local new_size=0

    while [ -f "$file" ]; do
        new_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        if [ "$new_size" -eq "$old_size" ]; then
            return 0
        fi
        old_size="$new_size"
        sleep 1
    done
    return 1
}

process_all() {
    local changed=0

    find "$WATCH" -type f -print0 | while IFS= read -r -d '' FILE
    do
        REL_PATH="${FILE#$WATCH/}"
        OUT_DIR="$DEST/$(dirname "$REL_PATH")"
        mkdir -p "$OUT_DIR"

        BASENAME="$(basename "$FILE")"
        NAME="${BASENAME%.*}"
        EXT="${FILE##*.}"
        EXT_LOWER="$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')"

        case "$EXT_LOWER" in
            wav)
                OUT_FILE="$OUT_DIR/$NAME.flac"
                if [ ! -f "$OUT_FILE" ] && [ -f "$FILE" ]; then
                    wait_until_stable "$FILE"
                    if [ -f "$FILE" ]; then
                        ffmpeg -nostdin -i "$FILE" -vn -map_metadata -1 -c:a flac -compression_level 8 "$OUT_FILE" -y 2>/dev/null && rm -f "$FILE"
                        changed=1
                    fi
                fi
                ;;
            mp3|flac|m4a|aac|ogg|opus)
                OUT_FILE="$OUT_DIR/$BASENAME"
                if [ ! -f "$OUT_FILE" ] && [ -f "$FILE" ]; then
                    wait_until_stable "$FILE"
                    if [ -f "$FILE" ]; then
                        mv -n -- "$FILE" "$OUT_FILE"
                        changed=1
                    fi
                fi
                ;;
            jpg|jpeg|png|webp|gif|bmp|mp4|m4v|mov)
                OUT_FILE="$OUT_DIR/$BASENAME"
                if [ ! -f "$OUT_FILE" ] && [ -f "$FILE" ]; then
                    wait_until_stable "$FILE"
                    if [ -f "$FILE" ]; then
                        mv -n -- "$FILE" "$OUT_FILE"
                        changed=1
                    fi
                fi
                ;;
        esac
    done

    find "$WATCH" -mindepth 1 -type d -empty -delete

    return 0
}

run_beets() {
    beet import /srv/media/music/library >/dev/null 2>>"$BEET_LOG"
}

main_cycle() {
    process_all
    run_beets
}

# 起動時に一度全部処理
main_cycle

# 完成したファイルだけ監視
inotifywait -m -r -e moved_to -e close_write "$WATCH" | while read -r path action file
do
    sleep 1
    main_cycle
done
