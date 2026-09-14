#!/bin/bash
set -euo pipefail
if [[ $EUID != 0 ]]; then echo 'Run this installer with sudo.' >&2; exit 1; fi
readonly source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
/usr/bin/id github-runner >/dev/null
/usr/bin/id volkh >/dev/null
if /usr/bin/id pc-lab >/dev/null 2>&1 || [[ -e /srv/pc-lab ]]; then
  echo 'pc-lab or /srv/pc-lab already exists. Stop to preserve the existing environment.' >&2
  exit 1
fi
command -v dockerd-rootless-setuptool.sh >/dev/null
command -v tailscale >/dev/null
lab_ip="$(tailscale ip -4)"
[[ $lab_ip =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
# Review these prerequisites before creating the dedicated account.
apt-get update
apt-get install -y uidmap dbus-user-session slirp4netns
useradd --create-home --home-dir /srv/pc-lab --shell /bin/bash pc-lab
chmod 700 /srv/pc-lab
# Normal useradd allocates subordinate IDs; refuse an incomplete configuration.
/usr/bin/grep -q '^pc-lab:' /etc/subuid
/usr/bin/grep -q '^pc-lab:' /etc/subgid
lab_uid="$(id -u pc-lab)"
loginctl enable-linger pc-lab
systemctl start "user@$lab_uid.service"
runuser -u pc-lab -- env -i HOME=/srv/pc-lab USER=pc-lab LOGNAME=pc-lab \
  PATH=/usr/local/bin:/usr/bin:/bin XDG_RUNTIME_DIR="/run/user/$lab_uid" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$lab_uid/bus" \
  /usr/bin/dockerd-rootless-setuptool.sh install --force
install -d -o pc-lab -g pc-lab -m 755 /srv/pc-lab/workspace /srv/pc-lab/workspace/www
install -o pc-lab -g pc-lab -m 644 "$source_dir/lab/compose.yaml" /srv/pc-lab/workspace/compose.yaml
printf 'TAILSCALE_IP=%s\n' "$lab_ip" > /srv/pc-lab/workspace/.env
chown pc-lab:pc-lab /srv/pc-lab/workspace/.env
chmod 600 /srv/pc-lab/workspace/.env
printf '<!doctype html><html lang="ja"><meta charset="utf-8"><title>PC Lab</title><h1>検証専用Dockerが動作しています</h1><p>GitHub Actions: Lab control</p></html>\n' > /srv/pc-lab/workspace/www/index.html
chown pc-lab:pc-lab /srv/pc-lab/workspace/www/index.html
install -o root -g root -m 755 "$source_dir/scripts/github-lab-control.sh" /usr/local/sbin/github-lab-control
sudo_rule="$(mktemp)"
trap 'rm -f "$sudo_rule"' EXIT
printf '%s\n' 'github-runner,volkh ALL=(root) NOPASSWD: /usr/local/sbin/github-lab-control' > "$sudo_rule"
visudo -cf "$sudo_rule"
install -o root -g root -m 440 "$sudo_rule" /etc/sudoers.d/pc-lab-control
/usr/local/sbin/github-lab-control up
/usr/local/sbin/github-lab-control status
# Test scope using the same entrypoint as Actions.
/usr/local/sbin/github-lab-control exec <<'CHECK'
test "$(id -un)" = pc-lab
test "$PWD" = /srv/pc-lab/workspace
test ! -w /var/run/docker.sock
test ! -w /etc/sudoers.d/pc-lab-control
test ! -r /home/volkh/.ssh
docker info --format '{{json .SecurityOptions}}' | grep -q rootless
printf 'Lab isolation checks passed.\n'
CHECK
curl --noproxy '*' --fail --silent http://127.0.0.1:18081/ >/dev/null
printf '\nInstalled. Local: http://127.0.0.1:18081 / Tailscale: http://%s:18081\n' "$lab_ip"
