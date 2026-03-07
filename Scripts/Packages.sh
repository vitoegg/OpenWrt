#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Lightweight UPDATE_PACKAGE function
# Usage: UPDATE_PACKAGE <pkg_name> <github_repo> <branch> <target_path>
#   pkg_name:    Package name (used to clean matching directories in feeds)
#   github_repo: GitHub repository (user/repo)
#   branch:      Branch name
#   target_path: Clone target path
UPDATE_PACKAGE() {
    local pkg_name=$1
    local pkg_repo=$2
    local pkg_branch=$3
    local pkg_target=$4

    # Step 1: Clean matching directories in feeds
    for feed_dir in feeds/packages feeds/luci; do
        if [ -d "$feed_dir" ]; then
            find "$feed_dir" -maxdepth 3 -type d -iname "*${pkg_name}*" 2>/dev/null | while read -r dir; do
                log "Removing existing $dir"
                rm -rf "$dir"
            done
        fi
    done

    # Step 2: Clone from GitHub
    log "Cloning $pkg_repo ($pkg_branch) to $pkg_target"
    git clone --depth=1 --single-branch -b "$pkg_branch" "https://github.com/${pkg_repo}.git" "$pkg_target"
}

# ===== Package Installation =====

# Nikki - personalized proxy package (nikki backend + luci-app-nikki)
# ImmortalWrt 24.10: NOT built-in (defensive removal with find)
UPDATE_PACKAGE "nikki" "vitoegg/OpenNikki" "master" "package/custom/OpenNikki"

# Argon Theme - customized version (background + footer modifications)
# ImmortalWrt 24.10: BUILT-IN v2.4.3, MUST remove before installing custom v2.4.2
UPDATE_PACKAGE "argon" "vitoegg/Argon" "main" "package/custom/luci-theme-argon"

# MosDNS LuCI - web management interface for mosdns
# ImmortalWrt 24.10: mosdns backend v5.3.3 built-in, but luci-app-mosdns NOT built-in
UPDATE_PACKAGE "luci-app-mosdns" "sbwml/luci-app-mosdns" "v5" "package/custom/luci-app-mosdns"

# ===== Dynamic Package Extension =====

# Support additional packages via WRT_PACKAGE environment variable
if [ -n "$WRT_PACKAGE" ]; then
    log "Installing additional packages: $WRT_PACKAGE"
    for pkg_entry in $WRT_PACKAGE; do
        # Format: name|repo|branch|target
        IFS='|' read -r name repo branch target <<< "$pkg_entry"
        if [ -n "$name" ] && [ -n "$repo" ]; then
            UPDATE_PACKAGE "$name" "$repo" "${branch:-main}" "${target:-package/custom/$name}"
        fi
    done
fi

log "Packages.sh completed"
