#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# REMOVE_FEEDS: Remove matching directories from feeds
# Usage: REMOVE_FEEDS <name> [name2] [name3] ...
#   Matches both exact name and luci-*name* patterns
REMOVE_FEEDS() {
    for name in "$@"; do
        log "Searching feeds: $name"
        local find_args=(-iname "$name")
        if [[ "$name" != luci-* ]]; then
            find_args+=(-o -iname "luci-*$name*")
        fi
        local found
        found=$(find feeds/luci/ feeds/packages/ -maxdepth 3 -type d \
            \( "${find_args[@]}" \) 2>/dev/null)
        if [ -n "$found" ]; then
            while read -r dir; do
                rm -rf "$dir"
                log "Removed feed: $dir"
            done <<< "$found"
        else
            log "Not found in feeds: $name"
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

# REMOVE_CONFLICT: Remove sub-directories from a cloned package to avoid upstream conflicts
# Usage: REMOVE_CONFLICT <package_name> <dir1> [dir2] [dir3] ...
REMOVE_CONFLICT() {
    local pkg=$1
    shift
    local target_dir="package/custom/$pkg"
    for dir in "$@"; do
        if [ -d "$target_dir/$dir" ]; then
            rm -rf "$target_dir/$dir"
            log "Removed conflicting: $target_dir/$dir"
        else
            log "Not found (skip): $target_dir/$dir"
        fi
    done
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

(
    REMOVE_FEEDS "argon"
    CLONE_PACKAGE "vitoegg/Argon" "main"
) &
pids+=($!)

(
    REMOVE_FEEDS "nikki"
    CLONE_PACKAGE "vitoegg/OpenNikki" "master"
) &
pids+=($!)

(
    REMOVE_FEEDS "mosdns" "v2dat"
    CLONE_PACKAGE "sbwml/luci-app-mosdns" "v5"
) &
pids+=($!)

if [ -n "$WRT_PACKAGE" ]; then
    log "Installing additional packages: $WRT_PACKAGE"
    for pkg_entry in $WRT_PACKAGE; do
        (
            IFS='|' read -r name repo branch mode pkg conflicts <<< "$pkg_entry"
            if [ -n "$repo" ]; then
                REMOVE_FEEDS "$name"
                CLONE_PACKAGE "$repo" "${branch:-main}" "$mode" "$pkg"
                if [ -n "$conflicts" ]; then
                    IFS=',' read -ra conflict_dirs <<< "$conflicts"
                    REMOVE_CONFLICT "${pkg:-${repo#*/}}" "${conflict_dirs[@]}"
                fi
            fi
        ) &
        pids+=($!)
    done
fi

for pid in "${pids[@]}"; do wait "$pid"; done
log "All packages installed"

log "Packages.sh completed"
