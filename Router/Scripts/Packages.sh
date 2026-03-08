#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# UPDATE_PACKAGE: Install/update packages from GitHub
# Usage: UPDATE_PACKAGE <pkg_name> <repo> <branch> [special] [extra_names]
#   special: "pkg" = extract sub-package; "name" = rename after clone
#   extra_names: additional directory names to clean (space-separated)
UPDATE_PACKAGE() {
    local pkg_name=$1
    local pkg_repo=$2
    local pkg_branch=$3
    local pkg_special=$4
    local pkg_extra="$5"
    local repo_name=${pkg_repo#*/}
    local pkg_list=("$pkg_name" $pkg_extra)

    # Step 1: Clean matching directories in feeds
    for name in "${pkg_list[@]}"; do
        log "Search directory: $name"
        local found_dirs=$(find feeds/luci/ feeds/packages/ -maxdepth 3 -type d \
            \( -iname "$name" -o -iname "luci-*$name*" \) 2>/dev/null)
        if [ -n "$found_dirs" ]; then
            while read -r dir; do
                rm -rf "$dir"
                log "Removed: $dir"
            done <<< "$found_dirs"
        else
            log "Not found: $name"
        fi
    done

    # Step 2: Clone from GitHub
    local clone_dir="package/custom/$repo_name"
    log "Cloning $pkg_repo ($pkg_branch) to $clone_dir"
    git clone --depth=1 --single-branch -b "$pkg_branch" "https://github.com/${pkg_repo}.git" "$clone_dir"

    # Step 3: Handle special modes
    if [[ "$pkg_special" == "pkg" ]]; then
        find "./$clone_dir/" -maxdepth 3 -type d -iname "*$pkg_name*" -prune \
            -exec cp -rf {} package/custom/ \;
        rm -rf "./$clone_dir"
        log "Extracted $pkg_name from $repo_name"
    elif [[ "$pkg_special" == "name" ]]; then
        mv -f "$clone_dir" "package/custom/$pkg_name"
        log "Renamed $repo_name to $pkg_name"
    fi
}

# ===== Package Installation =====

# Argon Theme
UPDATE_PACKAGE "argon" "vitoegg/Argon" "main"

# Nikki
UPDATE_PACKAGE "nikki" "vitoegg/OpenNikki" "master"

# MosDNS - branch-aware handling:
#   master: use sbwml's full package (backend + luci)
#   openwrt-24.10: keep ImmortalWrt built-in backend, only add sbwml LuCI frontend
if [[ "$WRT_BRANCH" == "master" ]]; then
    UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
else
    UPDATE_PACKAGE "luci-app-mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
    rm -rf "package/custom/luci-app-mosdns/mosdns"
fi

# ===== Dynamic Package Extension =====

if [ -n "$WRT_PACKAGE" ]; then
    log "Installing additional packages: $WRT_PACKAGE"
    for pkg_entry in $WRT_PACKAGE; do
        IFS='|' read -r name repo branch special extra <<< "$pkg_entry"
        if [ -n "$name" ] && [ -n "$repo" ]; then
            UPDATE_PACKAGE "$name" "$repo" "${branch:-main}" "$special" "$extra"
        fi
    done
fi

log "Packages.sh completed"
