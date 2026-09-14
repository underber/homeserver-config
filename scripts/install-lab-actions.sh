#!/bin/bash
set -euo pipefail
if [[ $EUID != 0 ]]; then echo 'Run this installer with sudo.' >&2; exit 1; fi
readonly source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
/usr/bin/id github-runner >/dev/null
/usr/bin/id volkh >/dev/null
# Resume this install, including the original /srv path on hosts where /srv
# resolves inside another user's private home. Never change that home's ACL.
existing_home="$(getent passwd pc-lab | cut -d: -f6 || true)"
if [[ -n $existing_home && $existing_home != /srv/pc-lab && $existing_home != /home/pc-lab ]]; then
  echo 'Unexpected pc-lab account home; refusing to change it.' >&2; exit 1
fi
if [[ -z $existing_home && -e /home/pc-lab ]]; then
  echo '/home/pc-lab already exists without the dedicated account.' >&2; exit 1
fi
command -v dockerd-rootless-setuptool.sh >/dev/null
command -v tailscale >/dev/null
lab_ip="$(tailscale ip -4)"
[[ $lab_ip =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
# Review these prerequisites before creating the dedicated account.
apt-get update
apt-get install -y uidmap dbus-user-session slirp4netns
if [[ -z $existing_home ]]; then
  useradd --create-home --home-dir /home/pc-lab --shell /bin/bash pc-lab
elif [[ $existing_home == /srv/pc-lab ]]; then
  [[ ! -e /home/pc-lab ]] || { echo 'Migration destination already exists.' >&2; exit 1; }
  loginctl disable-linger pc-lab
  loginctl terminate-user pc-lab
  systemctl stop "user@$(id -u pc-lab).service"
  usermod --home /home/pc-lab --move-home pc-lab
fi
[[ $(stat -c %u /home/pc-lab) == $(id -u pc-lab) ]]
chmod 700 /home/pc-lab
# Normal useradd allocates subordinate IDs; refuse an incomplete configuration.
/usr/bin/grep -q '^pc-lab:' /etc/subuid
/usr/bin/grep -q '^pc-lab:' /etc/subgid
lab_uid="$(id -u pc-lab)"
loginctl enable-linger pc-lab
systemctl start "user@$lab_uid.service"
runuser -u pc-lab -- env -i HOME=/home/pc-lab USER=pc-lab LOGNAME=pc-lab \
  PATH=/usr/local/bin:/usr/bin:/bin XDG_RUNTIME_DIR="/run/user/$lab_uid" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$lab_uid/bus" \
  /bin/bash --noprofile --norc -c 'cd "$HOME"; exec /usr/bin/dockerd-rootless-setuptool.sh install --force'
install -d -o pc-lab -g pc-lab -m 755 /home/pc-lab/workspace /home/pc-lab/workspace/www
if [[ ! -e /home/pc-lab/workspace/compose.yaml ]]; then
  install -o pc-lab -g pc-lab -m 644 "$source_dir/lab/compose.yaml" /home/pc-lab/workspace/compose.yaml
fi
if [[ ! -e /home/pc-lab/workspace/.env ]]; then
printf 'TAILSCALE_IP=%s\n' "$lab_ip" > /home/pc-lab/workspace/.env
chown pc-lab:pc-lab /home/pc-lab/workspace/.env
chmod 600 /home/pc-lab/workspace/.env
fi
if [[ ! -e /home/pc-lab/workspace/www/index.html ]]; then
printf '<!doctype html><html lang="ja"><meta charset="utf-8"><title>PC Lab</title><h1>検証専用Dockerが動作しています</h1><p>GitHub Actions: Lab control</p></html>\n' > /home/pc-lab/workspace/www/index.html
chown pc-lab:pc-lab /home/pc-lab/workspace/www/index.html
fi
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
test "$PWD" = /home/pc-lab/workspace
test ! -w /var/run/docker.sock
test ! -w /etc/sudoers.d/pc-lab-control
test ! -r /home/volkh/.ssh
docker info --format '{{json .SecurityOptions}}' | grep -q rootless
printf 'Lab isolation checks passed.\n'
CHECK
curl --noproxy '*' --fail --silent "http://$lab_ip:18081/" >/dev/null
printf '\nInstalled. This PC and Tailscale: http://%s:18081\n' "$lab_ip"
