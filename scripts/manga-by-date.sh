#!/usr/bin/env bash
# Rebuild /srv/media/manga/by-date/ with cbz symlinks numbered by mtime
# (the original archive's creation date — what the user calls "作成日").
# Newest gets 0001.

set -euo pipefail

LIBRARY="/srv/media/manga/library"
DEST="/srv/media/manga/by-date"

mkdir -p "$DEST"
find "$DEST" -mindepth 1 -delete

find "$LIBRARY" -type f -name '*.cbz' -printf '%T@\t%p\n' |
    sort -k1,1nr |
    awk -F'\t' '{print NR"\t"$2}' |
    while IFS=$'\t' read -r idx f; do
        base=$(basename "$f")
        base_noext="${base%.cbz}"
        series=$(basename "$(dirname "$f")")
        if [[ "$base_noext" == "$series" ]]; then
            name=$(printf '%04d_%s' "$idx" "$base")
        else
            name=$(printf '%04d_%s - %s' "$idx" "$series" "$base")
        fi
        ln -s "$f" "$DEST/$name" || echo "WARN: failed to link: $name" >&2
    done

count=$(find "$DEST" -mindepth 1 -maxdepth 1 -type l | wc -l)
echo "Created $count symlinks in $DEST"

# Sync each series-folder mtime to the newest cbz mtime inside it,
# so a "modified date" sort lists folders in archive-creation-date order.
find "$LIBRARY" -mindepth 1 -maxdepth 1 -type d -print0 |
    while IFS= read -r -d '' dir; do
        newest=$(find "$dir" -type f -name '*.cbz' -printf '%T@\n' |
                 sort -nr | head -1)
        [[ -n "$newest" ]] && touch -d "@${newest%.*}" "$dir"
    done

# Tell Nextcloud to refresh its DB so the new mtimes/symlinks are visible.
docker exec -u www-data nextcloud-app-1 \
    php occ files:scan --path='volkh/files/media/manga' --quiet \
    >/dev/null 2>&1 || true

# files:scan only updates storage_mtime, but the Web UI sorts by mtime.
# Force them in sync for the manga library.
docker exec nextcloud-db-1 psql -U nextcloud -d nextcloud -c \
    "UPDATE oc_filecache SET mtime = storage_mtime WHERE storage = 4 AND path LIKE 'manga/library/%' AND mtime != storage_mtime;" \
    >/dev/null 2>&1 || true
