#!/bin/bash
set -euo pipefail
# Installed root-owned; never source files from the writable lab as root.
if [[ $# != 1 ]]; then echo 'Usage: github-lab-control status|up|stop|down|logs|exec' >&2; exit 2; fi
case "$1" in
  status) command='docker info --format "Docker {{.ServerVersion}}"; docker compose ps' ;;
  up) command='docker compose up -d --wait --wait-timeout 120' ;;
  stop) command='docker compose stop' ;;
  down) command='docker compose down' ;;
  logs) command='docker compose logs --no-color --tail=100' ;;
  exec) command='' ;;
  *) echo 'Unsupported lab action' >&2; exit 2 ;;
esac
if [[ $EUID != 0 ]]; then echo 'Run through the installed sudo rule.' >&2; exit 1; fi
readonly lab_uid="$(/usr/bin/id -u pc-lab)"
readonly lab_home=/srv/pc-lab
readonly lab_runtime="/run/user/$lab_uid"
# env -i removes runner credentials and inherited Docker/shell configuration.
# The entire caller script runs AFTER dropping root privileges.
if [[ $1 == exec ]]; then
  exec /usr/sbin/runuser -u pc-lab -- /usr/bin/env -i \
    HOME="$lab_home" USER=pc-lab LOGNAME=pc-lab PATH=/usr/local/bin:/usr/bin:/bin \
    XDG_RUNTIME_DIR="$lab_runtime" DBUS_SESSION_BUS_ADDRESS="unix:path=$lab_runtime/bus" \
    DOCKER_HOST="unix://$lab_runtime/docker.sock" \
    /bin/bash --noprofile --norc -c 'cd "$HOME/workspace"; exec /bin/bash --noprofile --norc -e -o pipefail -s'
else
  exec /usr/sbin/runuser -u pc-lab -- /usr/bin/env -i \
    HOME="$lab_home" USER=pc-lab LOGNAME=pc-lab PATH=/usr/local/bin:/usr/bin:/bin \
    XDG_RUNTIME_DIR="$lab_runtime" DBUS_SESSION_BUS_ADDRESS="unix:path=$lab_runtime/bus" \
    DOCKER_HOST="unix://$lab_runtime/docker.sock" \
    /bin/bash --noprofile --norc -c 'cd "$HOME/workspace"; exec /bin/bash --noprofile --norc -e -o pipefail -c "$1"' lab "$command"
fi
