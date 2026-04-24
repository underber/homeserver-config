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

echo "==> Syncing docker-compose files  (~/docker/ -> docker/)"
sync_dir ~/docker "$REPO/docker"

echo "==> Syncing Caddyfile  (/etc/caddy/Caddyfile -> caddy/)"
sync_file /etc/caddy/Caddyfile "$REPO/caddy/Caddyfile"

echo "==> Syncing systemd user units  (~/.config/systemd/user/ -> systemd/user/)"
sync_dir ~/.config/systemd/user "$REPO/systemd/user"

echo "==> Syncing systemd system units  (/etc/systemd/system/*.local.* -> systemd/system/)"
# Only copy units you own — avoid pulling in distro-managed units.
if [[ -d /etc/systemd/system ]]; then
    mkdir -p "$REPO/systemd/system"
    # Copy *.service / *.timer / *.mount that are not symlinks to /lib (distro units).
    find /etc/systemd/system \
        -maxdepth 1 \
        \( -name '*.service' -o -name '*.timer' -o -name '*.mount' -o -name '*.socket' \) \
        ! -type l \
        -exec cp {} "$REPO/systemd/system/" \;
    ok "/etc/systemd/system/ (non-symlink units)"
else
    skip "/etc/systemd/system/ (not found)"
fi

echo "==> Syncing scripts  (~/scripts/ -> scripts/)"
sync_dir ~/scripts "$REPO/scripts"

echo ""
echo "Done. Review with: git -C '$REPO' diff"
