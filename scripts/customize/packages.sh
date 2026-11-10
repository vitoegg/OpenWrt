#!/bin/bash

# Clones the custom packages and removes the feed packages they replace

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"

load_profile "${1:?Usage: packages.sh <Router|Cloud>}"

# sdk.sh and imagebuilder.sh rely on the same paths
PKG_CLONE_BASE="package/custom"
APPS_BASELINE=".apps-baseline.json"

clone_package() {
    local repo="$1"
    local branch="${2:-}"
    local dest_name="${3:-}"
    local dest
    local branch_args=()

    dest_name=${dest_name:-${repo#*/}}
    dest="$PKG_CLONE_BASE/$dest_name"

    if [ -n "$branch" ]; then
        branch_args=(--branch "$branch")
    fi

    mkdir -p "$PKG_CLONE_BASE"
    group "Clone $repo"
    git clone --depth=1 --single-branch "${branch_args[@]}" \
        "https://github.com/${repo}.git" "$dest" || die "Failed to clone $repo"
    endgroup
    record_app_baseline "$dest_name" "$repo" "$branch" "$dest"
    log_ok "$dest_name: $repo${branch:+@$branch} ($(git -C "$dest" rev-parse --short HEAD))"
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

clone_packages() {
    local entry
    local repo
    local branch
    local dest_name

    section "Custom Packages"

    for entry in "${PACKAGE_CLONES[@]}"; do
        IFS='|' read -r repo branch dest_name <<< "$entry"
        clone_package "$repo" "$branch" "$dest_name"
    done
}

# OpenWrt does not detect duplicate package names, the cloned package must win
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
            log_ok "Feed package replaced: ${link#package/feeds/}"
        done
    done < <(find "$PKG_CLONE_BASE" -mindepth 2 -maxdepth 3 -name Makefile | sort)
}

clone_packages
shadow_feed_duplicates
