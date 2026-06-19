#!/bin/bash -e

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_profile "${1:?Usage: ApplyPackages.sh <Router|Cloud>}"

PKG_SEARCH_PATHS=${PKG_SEARCH_PATHS:-"feeds/luci/ feeds/packages/"}
PKG_CLONE_BASE=${PKG_CLONE_BASE:-"package/custom"}

remove_package() {
    local name
    local found
    local dir

    for name in "$@"; do
        log "Removing: $name"
        found=$(find $PKG_SEARCH_PATHS -maxdepth 3 -type d -iname "*$name*" 2>/dev/null || true)

        if [ -n "$found" ]; then
            while IFS= read -r dir; do
                [ -n "$dir" ] || continue
                rm -rf "$dir"
                log "Removed: $dir"
            done <<< "$found"
        else
            log "Not found: $name"
        fi
    done
}

clone_package() {
    local repo="$1"
    local branch="${2:-}"
    local dest_name="${3:-}"
    local dest
    local start
    local branch_label="default"
    local branch_args=()

    dest_name=${dest_name:-${repo#*/}}
    dest="$PKG_CLONE_BASE/$dest_name"
    start=$SECONDS

    if [ -n "$branch" ]; then
        branch_args=(--branch "$branch")
        branch_label="$branch"
    fi

    mkdir -p "$PKG_CLONE_BASE"
    log "Cloning $repo ($branch_label) -> $dest"
    if ! git clone --depth=1 --single-branch "${branch_args[@]}" \
        "https://github.com/${repo}.git" "$dest"; then
        log "ERROR: Failed to clone $repo"
        return 1
    fi
    log "Cloned $repo ($((SECONDS - start))s)"
}

apply_configured_packages() {
    local entry
    local repo
    local branch
    local dest_name
    local name

    section "Built-in Package Changes"

    if [ "${#PACKAGE_REMOVES[@]}" -gt 0 ]; then
        remove_package "${PACKAGE_REMOVES[@]}"
    fi

    for entry in "${PACKAGE_CLONES[@]}"; do
        IFS='|' read -r repo branch dest_name <<< "$entry"
        [ -n "$repo" ] || continue
        clone_package "$repo" "$branch" "$dest_name"
    done

    if [ -n "$WRT_PACKAGE" ]; then
        section "Extra Packages"
        log "Installing additional packages: $WRT_PACKAGE"
        for entry in $WRT_PACKAGE; do
            IFS='|' read -r name repo branch dest_name <<< "$entry"
            if [ -n "$repo" ]; then
                remove_package "$name"
                clone_package "$repo" "$branch" "$dest_name"
            fi
        done
    fi
}

apply_configured_packages

log "ApplyPackages.sh completed"
