#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# REMOVE_FEEDS: Remove matching directories from feeds
# Usage: REMOVE_FEEDS <name> [name2] [name3] ...
#   Matches both exact name and luci-*name* patterns
REMOVE_FEEDS() {
    for name in "$@"; do
        log "Search: $name"
        local find_args=(-iname "$name")
        # For short names (e.g. "argon"), also match luci-*name* variants
        # For full luci names (e.g. "luci-app-mosdns"), exact match only
        if [[ "$name" != luci-* ]]; then
            find_args+=(-o -iname "luci-*$name*")
        fi
        local found
        found=$(find feeds/luci/ feeds/packages/ -maxdepth 3 -type d \
            \( "${find_args[@]}" \) 2>/dev/null)
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

# CLONE_PACKAGE: Clone a GitHub repo into package/custom/
# Usage: CLONE_PACKAGE <repo> <branch> [mode] [pkg_name]
#   mode: "pkg" = extract sub-directory matching pkg_name
#         "name" = rename repo dir to pkg_name
CLONE_PACKAGE() {
    local repo=$1
    local branch=$2
    local mode=$3
    local pkg_name=$4
    local repo_name=${repo#*/}
    local clone_dir="package/custom/$repo_name"

    log "Cloning $repo ($branch)"
    git clone --depth=1 --single-branch -b "$branch" "https://github.com/${repo}.git" "$clone_dir"

    if [[ "$mode" == "pkg" ]]; then
        find "./$clone_dir/" -maxdepth 3 -type d -iname "*$pkg_name*" -prune \
            -exec cp -rf {} package/custom/ \;
        rm -rf "./$clone_dir"
        log "Extracted $pkg_name from $repo_name"
    elif [[ "$mode" == "name" ]]; then
        mv -f "$clone_dir" "package/custom/$pkg_name"
        log "Renamed $repo_name to $pkg_name"
    fi
}

# ===== Package Installation =====

# Argon Theme
REMOVE_FEEDS "argon"
CLONE_PACKAGE "vitoegg/Argon" "main"

# Nikki
REMOVE_FEEDS "nikki"
CLONE_PACKAGE "vitoegg/OpenNikki" "master"

# MosDNS - use upstream version (backend + luci + v2dat)
REMOVE_FEEDS "mosdns" "v2dat"
CLONE_PACKAGE "sbwml/luci-app-mosdns" "v5"

# Remove packages with unsatisfied dependencies (upstream feeds issue)
REMOVE_FEEDS "onionshare-cli"

# ===== Dynamic Package Extension =====

if [ -n "$WRT_PACKAGE" ]; then
    log "Installing additional packages: $WRT_PACKAGE"
    for pkg_entry in $WRT_PACKAGE; do
        IFS='|' read -r name repo branch mode pkg <<< "$pkg_entry"
        if [ -n "$repo" ]; then
            REMOVE_FEEDS "$name"
            CLONE_PACKAGE "$repo" "${branch:-main}" "$mode" "$pkg"
        fi
    done
fi

log "Packages.sh completed"
