#!/usr/bin/env bash
# Pulls live config files from their canonical locations into this repo.
# Run before "git add" to capture current state.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

ok()   { echo "  [ok] $*"; }
skip() { echo "  [--] $*"; }
warn() { echo "  [!!] $*" >&2; }

sync_file() {
    local src="$1" dst="$2"
    if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        ok "$src"
    else
        skip "$src (not found)"
    fi
}

sync_dir() {
    local src="$1" dst="$2"
    shift 2
    local extra_excludes=("$@")

    if [[ ! -d "$src" ]]; then
        skip "$src/ (not found)"
        return
    fi

    mkdir -p "$dst"
    rsync -a --delete \
        --exclude='.env' \
        --exclude='*.env' \
        --exclude='secrets/' \
        --exclude='*.secret' \
        --exclude='*.key' \
        --exclude='*.pem' \
        --exclude='data/' \
        --exclude='db/' \
        --exclude='media/' \
        --exclude='downloads/' \
        --exclude='cache/' \
        "${extra_excludes[@]+"${extra_excludes[@]}"}" \
        "$src/" "$dst/"
    ok "$src/"
}

echo "==> Syncing docker compose files  (/srv/docker/ -> docker/)"
for svc in /srv/docker/*/; do
    name="$(basename "$svc")"
    for f in docker-compose.yml compose.yml; do
        if [[ -f "$svc$f" ]]; then
            dst="$REPO/docker/$name/$f"
            mkdir -p "$(dirname "$dst")"
            cp "$svc$f" "$dst"
            ok "$svc$f"
            break
        fi
    done
done

echo "==> Syncing Caddyfile  (/etc/caddy/Caddyfile -> caddy/)"
sync_file /etc/caddy/Caddyfile "$REPO/caddy/Caddyfile"

echo "==> Syncing systemd user units  (~/.config/systemd/user/ -> systemd/user/)"
sync_dir ~/.config/systemd/user "$REPO/systemd/user"

echo "==> Syncing systemd system units  (/etc/systemd/system/ -> systemd/system/)"
if [[ -d /etc/systemd/system ]]; then
    mkdir -p "$REPO/systemd/system"
    find /etc/systemd/system \
        -maxdepth 1 \
        \( -name '*.service' -o -name '*.timer' -o -name '*.mount' -o -name '*.socket' \) \
        ! -type l \
        -exec cp {} "$REPO/systemd/system/" \;
    ok "/etc/systemd/system/ (non-symlink units)"
else
    skip "/etc/systemd/system/ (not found)"
fi

echo "==> Syncing scripts  (/srv/scripts/ -> scripts/)"
sync_dir /srv/scripts "$REPO/scripts"

echo ""
echo "Done. Review with: git -C '$REPO' diff"
