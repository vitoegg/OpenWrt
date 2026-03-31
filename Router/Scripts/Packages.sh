#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# REMOVE_PKG: Remove matching package directories from feeds
# Usage: REMOVE_PKG <name> [name2] [name3] ...
REMOVE_PKG() {
    for name in "$@"; do
        log "Searching: $name"
        local found
        found=$(find feeds/luci/ feeds/packages/ -maxdepth 3 -type d -iname "*$name*" 2>/dev/null)
        if [ -n "$found" ]; then
            while read -r dir; do
                rm -rf "$dir"
                log "Removed: $dir"
            done <<< "$found"
        else
            log "Not found: $name"
        fi
    done
}

# CLONE_PKG: Clone a GitHub repo into package/custom/
# Usage: CLONE_PKG <repo> <branch> [dest_name]
#   dest_name: optional directory name (defaults to repo basename)
CLONE_PKG() {
    local repo=$1
    local branch=$2
    local dest_name=${3:-${repo#*/}}
    local dest="package/custom/$dest_name"
    log "Cloning $repo ($branch) -> $dest"
    git clone --depth=1 --single-branch -b "$branch" "https://github.com/${repo}.git" "$dest"
}

# ===== Go Toolchain Upgrade (non-master branches) =====

if [ -n "$WRT_BRANCH" ] && [ "$WRT_BRANCH" != "master" ]; then
    log "Upgrading Go toolchain for branch: $WRT_BRANCH"
    rm -rf feeds/packages/lang/golang
    git clone --depth=1 --single-branch -b 26.x \
        https://github.com/sbwml/packages_lang_golang.git \
        feeds/packages/lang/golang
    log "Go toolchain upgraded successfully"
fi

# ===== Package Installation (parallel) =====

pids=()

# ===== Apps to install =====
(
    REMOVE_PKG "argon"
    CLONE_PKG "vitoegg/Argon" "main" "luci-theme-argon"
) &
pids+=($!)

(
    REMOVE_PKG "nikki"
    CLONE_PKG "vitoegg/OpenNikki" "master"
) &
pids+=($!)

(
    REMOVE_PKG "mosdns" "v2dat"
    CLONE_PKG "sbwml/luci-app-mosdns" "v5"
) &
pids+=($!)

# ===== Apps not needed =====
(
    REMOVE_PKG \
        "onionshare-cli" \
        "luci-app-mjpg-streamer"
) &
pids+=($!)

if [ -n "$WRT_PACKAGE" ]; then
    log "Installing additional packages: $WRT_PACKAGE"
    for pkg_entry in $WRT_PACKAGE; do
        (
            IFS='|' read -r name repo branch dest_name <<< "$pkg_entry"
            if [ -n "$repo" ]; then
                REMOVE_PKG "$name"
                CLONE_PKG "$repo" "${branch:-main}" "$dest_name"
            fi
        ) &
        pids+=($!)
    done
fi

for pid in "${pids[@]}"; do wait "$pid"; done
log "All packages installed"

log "Packages.sh completed"
