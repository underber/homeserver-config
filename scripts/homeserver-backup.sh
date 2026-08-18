#!/usr/bin/env bash
set -euo pipefail

umask 077
ENV_FILE="${BACKUP_ENV_FILE:-/etc/homeserver-backup.env}"
STAGE="${BACKUP_STAGE:-/srv/backup/staging}"
CACHE="${BACKUP_CACHE:-/srv/backup/cache}"

[[ -r "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
# Export sourced values so restic and docker subprocesses receive them.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
: "${RESTIC_REPOSITORY:?Set RESTIC_REPOSITORY in $ENV_FILE}"
: "${RESTIC_PASSWORD_FILE:?Set RESTIC_PASSWORD_FILE in $ENV_FILE}"

install -d -m 0700 "$STAGE" "$CACHE"
export XDG_CACHE_HOME="$CACHE"
maintenance=0
cleanup() {
    if (( maintenance )); then
        docker exec -u www-data nextcloud-app-1 php occ maintenance:mode --off >/dev/null || true
    fi
    find "$STAGE" -mindepth 1 -delete
}
trap cleanup EXIT

# Keep Nextcloud files and its database mutually consistent while restic reads them.
docker exec -u www-data nextcloud-app-1 php occ maintenance:mode --on
maintenance=1
docker exec nextcloud-db-1 pg_dumpall -U "${POSTGRES_USER:-nextcloud}" \
    | gzip -c >"$STAGE/nextcloud-postgres.sql.gz"
mkdir -p "$STAGE/portainer-data"
docker cp portainer:/data/. "$STAGE/portainer-data/"

restic backup \
    /srv/docker /srv/scripts /etc/caddy /etc/systemd/system \
    /var/lib/docker/volumes/nextcloud_nextcloud_data/_data "$STAGE" \
    --one-file-system \
    --exclude='**/cache/**' \
    --exclude='**/*.log'

docker exec -u www-data nextcloud-app-1 php occ maintenance:mode --off
maintenance=0

restic forget --keep-daily 7 --keep-weekly 5 --keep-monthly 12 --prune
restic check --read-data-subset=5%
