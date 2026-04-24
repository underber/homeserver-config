#!/usr/bin/env bash
# Run once on a fresh machine to wire up this repo and optionally deploy configs.
# Usage:
#   ./setup-git.sh                  # check status only
#   ./setup-git.sh --deploy         # copy tracked configs to their live locations
#   ./setup-git.sh --remote <url>   # set/replace origin remote

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

deploy=false
remote_url=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --deploy)  deploy=true; shift ;;
        --remote)  remote_url="$2"; shift 2 ;;
        *)         echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

# ── Remote setup ─────────────────────────────────────────────────────────────
if [[ -n "$remote_url" ]]; then
    if git -C "$REPO" remote get-url origin &>/dev/null; then
        git -C "$REPO" remote set-url origin "$remote_url"
        echo "[ok] Updated origin -> $remote_url"
    else
        git -C "$REPO" remote add origin "$remote_url"
        echo "[ok] Added origin -> $remote_url"
    fi
fi

# ── Status report ─────────────────────────────────────────────────────────────
echo ""
echo "Repo:   $REPO"
echo "Remote: $(git -C "$REPO" remote get-url origin 2>/dev/null || echo '(none — set with --remote <url>)')"
echo "Branch: $(git -C "$REPO" branch --show-current)"
echo ""
git -C "$REPO" log --oneline -5 2>/dev/null || echo "(no commits yet)"

# ── Deploy (repo -> live locations) ───────────────────────────────────────────
if $deploy; then
    echo ""
    echo "==> Deploying configs to live locations..."

    deploy_file() {
        local src="$1" dst="$2"
        if [[ -f "$src" ]]; then
            sudo mkdir -p "$(dirname "$dst")"
            sudo cp "$src" "$dst"
            echo "  [ok] -> $dst"
        fi
    }

    deploy_dir() {
        local src="$1" dst="$2"
        if [[ -d "$src" ]]; then
            sudo mkdir -p "$dst"
            sudo rsync -a "$src/" "$dst/"
            echo "  [ok] -> $dst/"
        fi
    }

    # Caddy
    deploy_file "$REPO/caddy/Caddyfile" /etc/caddy/Caddyfile
    if command -v systemctl &>/dev/null; then
        sudo systemctl reload caddy 2>/dev/null && echo "  [ok] caddy reloaded" || true
    fi

    # Systemd system units
    deploy_dir "$REPO/systemd/system" /etc/systemd/system
    sudo systemctl daemon-reload 2>/dev/null && echo "  [ok] systemd reloaded" || true

    # Systemd user units
    deploy_dir "$REPO/systemd/user" ~/.config/systemd/user
    systemctl --user daemon-reload 2>/dev/null && echo "  [ok] systemd --user reloaded" || true

    # Docker compose stacks
    deploy_dir "$REPO/docker" ~/docker

    # Scripts
    if [[ -d "$REPO/scripts" ]]; then
        mkdir -p ~/scripts
        rsync -a "$REPO/scripts/" ~/scripts/
        chmod +x ~/scripts/*.sh 2>/dev/null || true
        echo "  [ok] -> ~/scripts/"
    fi

    echo ""
    echo "Deploy complete. Add .env files manually (they are excluded from git)."
fi
