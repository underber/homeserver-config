#!/usr/bin/env bash
set -euo pipefail

STATE_DIR=/var/lib/homeserver-healthcheck
STATE_FILE="$STATE_DIR/state"
NEXTCLOUD_CONTAINER=${NEXTCLOUD_CONTAINER:-nextcloud-app-1}
NEXTCLOUD_USER=${NEXTCLOUD_USER:-volkh}
SERVICES=(nextcloud-app-1 nextcloud-db-1 jellyfin vaultwarden syncthing portainer)
SYSTEM_SERVICES=(AdGuardHome.service caddy.service tailscaled.service)

install -d -m 0750 "$STATE_DIR"
problems=()
for service in "${SERVICES[@]}"; do
    state=$(docker inspect -f '{{.State.Status}}' "$service" 2>/dev/null || true)
    [[ "$state" == running ]] || problems+=("$service:$state")
done

for service in "${SYSTEM_SERVICES[@]}"; do
    systemctl is-active --quiet "$service" || problems+=("$service:inactive")
done

# Verify DNS through the same Tailscale address distributed to clients.
tailscale_ipv4=$(tailscale ip -4 2>/dev/null || true)
if [[ -z "$tailscale_ipv4" ]] || ! dig +short +time=2 +tries=1 @"$tailscale_ipv4" example.com A | grep -q .; then
    problems+=("tailscale-dns:unavailable")
fi

root_used=$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
media_used=$(df -P /srv/media | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
(( root_used < 90 )) || problems+=("root-disk:${root_used}%")
(( media_used < 95 )) || problems+=("media-disk:${media_used}%")

if systemctl is-failed --quiet homeserver-backup.service; then
    problems+=("backup:failed")
fi

if ((${#problems[@]})); then
    current="ERROR ${problems[*]}"
else
    current=OK
fi
previous=$(cat "$STATE_FILE" 2>/dev/null || true)
printf '%s\n' "$current" >"$STATE_FILE"

[[ "$current" == "$previous" ]] && exit 0
if [[ "$current" == OK ]]; then
    [[ -z "$previous" ]] && exit 0
    message="ホームサーバーは復旧しました"
else
    message="ホームサーバー異常: ${current#ERROR }"
fi
if ! docker exec -u www-data "$NEXTCLOUD_CONTAINER" php occ notification:generate "$NEXTCLOUD_USER" "$message"; then
    printf 'warning: failed to send Nextcloud notification\n' >&2
fi
