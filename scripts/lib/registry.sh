#!/bin/bash

# GHCR helpers for the artifacts scripts

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

WORKSPACE=""

cleanup_workspace() {
    if [ -n "$WORKSPACE" ]; then
        rm -rf "$WORKSPACE"
    fi
}

make_workspace() {
    WORKSPACE=$(mktemp -d)
    trap cleanup_workspace EXIT
}

# Usage: package_ref <tag> [imagebuilder|sdk|cache]
package_ref() {
    printf 'ghcr.io/%s/openwrt-%s:%s' \
        "${GITHUB_REPOSITORY_OWNER:?GITHUB_REPOSITORY_OWNER is required}" \
        "${2:-imagebuilder}" "$1" | tr '[:upper:]' '[:lower:]'
}

registry_cutoff() {
    date -u +'%Y-%m-%dT%H:%M:%SZ'
}

registry_login() {
    local ref="$1"
    local registry="${ref%%/*}"

    if [ -z "${GHCR_TOKEN:-}" ]; then
        log "No GHCR token, using anonymous access to $registry"
        return 0
    fi

    printf '%s' "$GHCR_TOKEN" | oras login "$registry" \
        --username "${GITHUB_ACTOR:-github-actions}" --password-stdin >/dev/null
}

# Removes the untagged versions a push left behind, never fails the caller
prune_stale_versions() {
    local ref="$1"
    local cutoff="$2"
    local package="${ref%:*}"
    local versions_api
    local stale_ids
    local version_id

    package="${package##*/}"
    versions_api="/users/${GITHUB_REPOSITORY_OWNER}/packages/container/${package}/versions"

    if [ -z "${GH_TOKEN:-}" ] || ! command -v gh >/dev/null 2>&1; then
        log_warn "No gh token, skipping stale version cleanup"
        return 0
    fi

    if ! stale_ids=$(PRUNE_CUTOFF="$cutoff" gh api --paginate "$versions_api" --jq '
            .[]
            | select(.created_at < $ENV.PRUNE_CUTOFF)
            | select(.metadata.container.tags | length == 0)
            | .id' 2>/dev/null); then
        log_warn "Failed to list versions of $package"
        return 0
    fi

    while IFS= read -r version_id; do
        [ -n "$version_id" ] || continue

        if gh api --method DELETE "$versions_api/$version_id" >/dev/null 2>&1; then
            log "Removed stale version: $package/$version_id"
        else
            log_warn "Failed to remove stale version: $package/$version_id"
        fi
    done <<< "$stale_ids"
}
