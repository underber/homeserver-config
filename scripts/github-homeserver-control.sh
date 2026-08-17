#!/usr/bin/env bash
set -euo pipefail

readonly ACTION="${1:-}"

show_service() {
  local unit="$1"
  printf '%-36s active=%-10s enabled=%s\n' \
    "$unit" \
    "$(systemctl is-active "$unit" 2>/dev/null || true)" \
    "$(systemctl is-enabled "$unit" 2>/dev/null || true)"
}

case "$ACTION" in
  status)
    echo "Host: $(hostname)"
    echo "Time: $(date --iso-8601=seconds)"
    echo
    show_service manga-zip2cbz.service
    show_service manga-by-date.service
    show_service media-library-watch.service
    show_service media-library-refresh.service
    show_service homeserver-backup.timer
    echo
    df -h /srv/media | sed -n '1,2p'
    ;;

  manga-rescan)
    systemctl start media-library-refresh.service
    echo "Media library refresh completed successfully."
    ;;

  restart-manga)
    systemctl restart manga-zip2cbz.service manga-by-date.service
    systemctl --quiet is-active manga-zip2cbz.service manga-by-date.service
    echo "Manga watchers restarted successfully."
    ;;

  manga-log)
    journalctl --no-pager -n 100 \
      -u manga-zip2cbz.service \
      -u manga-by-date.service
    ;;

  backup-status)
    show_service homeserver-backup.timer
    systemctl list-timers --no-pager homeserver-backup.timer
    journalctl --no-pager -n 60 -u homeserver-backup.service
    ;;

  *)
    echo "Unsupported action: $ACTION" >&2
    echo "Allowed actions: status, manga-rescan, restart-manga, manga-log, backup-status" >&2
    exit 2
    ;;
esac
