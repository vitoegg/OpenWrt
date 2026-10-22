#!/bin/bash -e

source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

load_profile "${1:?Usage: ApplyPackages.sh <Router|Cloud>}"

PKG_CLONE_BASE=${PKG_CLONE_BASE:-"package/custom"}
APPS_BASELINE=${APPS_BASELINE:-".apps-baseline.json"}

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
    record_app_baseline "$dest_name" "$repo" "$branch" "$dest"
    log "Cloned $repo ($((SECONDS - start))s)"
}

record_app_baseline() {
    local name="$1"
    local repo="$2"
    local branch="$3"
    local dest="$4"
    local commit

    commit=$(git -C "$dest" rev-parse HEAD 2>/dev/null) || return 0

    [ -f "$APPS_BASELINE" ] || printf '{}' > "$APPS_BASELINE"
    jq --arg n "$name" --arg r "$repo" --arg b "$branch" --arg c "$commit" \
        '.[$n] = {repo: $r, branch: $b, commit: $c}' \
        "$APPS_BASELINE" > "$APPS_BASELINE.tmp"
    mv "$APPS_BASELINE.tmp" "$APPS_BASELINE"
}

apply_configured_packages() {
    local entry
    local repo
    local branch
    local dest_name

    section "Built-in Package Changes"

    for entry in "${PACKAGE_CLONES[@]}"; do
        IFS='|' read -r repo branch dest_name <<< "$entry"
        [ -n "$repo" ] || continue
        clone_package "$repo" "$branch" "$dest_name"
    done
}

# Uninstall feed packages that share a name with a cloned package,
# OpenWrt does not detect duplicate package names
shadow_feed_duplicates() {
    local makefile
    local name
    local link

    [ -d "$PKG_CLONE_BASE" ] || return 0

    section "Feed Duplicates"

    while IFS= read -r makefile; do
        name=$(basename "$(dirname "$makefile")")
        for link in package/feeds/*/"$name"; do
            [ -L "$link" ] || continue
            rm -f "$link"
            log "Shadowed: ${link#package/feeds/}"
        done
    done < <(find "$PKG_CLONE_BASE" -mindepth 2 -maxdepth 3 -name Makefile | sort)
}

apply_configured_packages
shadow_feed_duplicates

log "ApplyPackages.sh completed"
