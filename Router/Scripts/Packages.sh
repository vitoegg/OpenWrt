#!/bin/bash -e

# ===== Variant Configuration =====
PKG_SEARCH_PATHS="feeds/luci/ feeds/packages/"
PKG_CLONE_BASE="package/custom"

# ===== Common Helper Functions =====

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

section() {
    echo ""
    echo "========== $1 =========="
}

# REMOVE_PKG: Remove matching package directories
# Usage: REMOVE_PKG <name> [name2] [name3] ...
REMOVE_PKG() {
    for name in "$@"; do
        log "Removing: $name"
        local found
        found=$(find $PKG_SEARCH_PATHS -maxdepth 3 -type d -iname "*$name*" 2>/dev/null)
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

# CLONE_PKG: Clone a GitHub repo into $PKG_CLONE_BASE/
# Usage: CLONE_PKG <repo> [--branch <branch>] [--name <dest_name>]
#   Omit --branch to use the repo's default branch
CLONE_PKG() {
    local repo=$1; shift
    local branch="" dest_name=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --branch) branch=$2; shift 2 ;;
            --name)   dest_name=$2; shift 2 ;;
            *)        shift ;;
        esac
    done
    dest_name=${dest_name:-${repo#*/}}
    local dest="$PKG_CLONE_BASE/$dest_name"
    local start=$SECONDS
    local branch_args=""
    local branch_label="default"
    if [ -n "$branch" ]; then
        branch_args="-b $branch"
        branch_label="$branch"
    fi
    log "Cloning $repo ($branch_label) -> $dest"
    if ! git clone --depth=1 --single-branch $branch_args \
        "https://github.com/${repo}.git" "$dest"; then
        log "ERROR: Failed to clone $repo"
        return 1
    fi
    log "Cloned $repo ($((SECONDS - start))s)"
}

# ===== Go Toolchain Upgrade (non-master branches) =====

if [ -n "$WRT_BRANCH" ] && [ "$WRT_BRANCH" != "master" ]; then
    section "Go Toolchain"
    log "Upgrading Go toolchain for branch: $WRT_BRANCH"
    rm -rf feeds/packages/lang/golang
    if ! git clone --depth=1 --single-branch -b 26.x \
        https://github.com/sbwml/packages_lang_golang.git \
        feeds/packages/lang/golang; then
        log "ERROR: Failed to upgrade Go toolchain"
        exit 1
    fi
    log "Go toolchain upgraded successfully"
fi

# ===== Package Installation =====

section "Package Installation"

# Argon - replace built-in with customized theme
REMOVE_PKG "argon"
CLONE_PKG "vitoegg/Argon" --name "luci-theme-argon"

# Nikki - replace built-in with customized version
REMOVE_PKG "nikki"
CLONE_PKG "vitoegg/OpenNikki"

# MosDNS - replace built-in with customized version
REMOVE_PKG "mosdns" "v2dat"
CLONE_PKG "sbwml/luci-app-mosdns" --branch "v5"

# v2ray-geodata - replace built-in with customized version
REMOVE_PKG "v2ray-geodata"
CLONE_PKG "sbwml/v2ray-geodata"

# Apps not needed
REMOVE_PKG \
    "onionshare-cli" \
    "luci-app-mjpg-streamer"

# Dynamic package installation from workflow
if [ -n "$WRT_PACKAGE" ]; then
    section "Dynamic Packages"
    log "Installing additional packages: $WRT_PACKAGE"
    for pkg_entry in $WRT_PACKAGE; do
        IFS='|' read -r name repo branch dest_name <<< "$pkg_entry"
        if [ -n "$repo" ]; then
            REMOVE_PKG "$name"
            local clone_args=("$repo")
            [ -n "$branch" ] && clone_args+=(--branch "$branch")
            [ -n "$dest_name" ] && clone_args+=(--name "$dest_name")
            CLONE_PKG "${clone_args[@]}"
        fi
    done
fi

log "Packages.sh completed"
