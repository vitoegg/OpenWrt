#!/bin/bash -e

set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

ARTIFACT_TYPE='application/vnd.openwrt.imagebuilder.v1+tar+zstd'
WORKSPACE=""

cleanup() {
    if [ -n "$WORKSPACE" ]; then
        rm -rf "$WORKSPACE"
    fi
}

make_workspace() {
    WORKSPACE=$(mktemp -d)
    trap cleanup EXIT
}

unavailable() {
    log "ImageBuilder unavailable: $1"
    exit 2
}

require_command() {
    local name="$1"

    if ! command -v "$name" >/dev/null 2>&1; then
        log "ERROR: $name not found"
        exit 1
    fi
}

require_profile() {
    case "${1:-}" in
        Router|Cloud)
            ;;
        *)
            log "ERROR: Unsupported build profile: ${1:-empty}"
            exit 1
            ;;
    esac
}

# Each profile owns one immutable tag, so publishing overwrites in place.
package_ref() {
    local profile="$1"
    local package="${IMAGEBUILDER_PACKAGE:-ghcr.io/${GITHUB_REPOSITORY_OWNER:?GITHUB_REPOSITORY_OWNER is required}/openwrt-imagebuilder}"

    printf '%s:%s' "$package" "$profile" | tr '[:upper:]' '[:lower:]'
}

registry_login() {
    local ref="$1"
    local registry="${ref%%/*}"

    if [ -z "${GHCR_TOKEN:-}" ]; then
        log "GHCR token not provided, using anonymous access for $registry"
        return 0
    fi

    printf '%s' "$GHCR_TOKEN" | oras login "$registry" \
        --username "${GITHUB_ACTOR:-github-actions}" --password-stdin >/dev/null
}

extract_packages() {
    awk 'NF >= 3 && $2 == "-" {print $1}' "$1" | sort -u
}

# Overwriting a tag leaves the previous manifest untagged; drop it so each
# profile keeps exactly one artifact in the package.
prune_untagged_versions() {
    local ref="$1"
    local package="${ref%:*}"
    local versions_api
    local stale_ids
    local version_id

    package="${package##*/}"
    versions_api="/users/${GITHUB_REPOSITORY_OWNER}/packages/container/${package}/versions"

    if [ -z "${GH_TOKEN:-}" ] || ! command -v gh >/dev/null 2>&1; then
        log "WARNING: gh token unavailable, skipping untagged cleanup"
        return 0
    fi

    if ! stale_ids=$(gh api --paginate "$versions_api" \
        --jq '.[] | select((.metadata.container.tags | length) == 0) | .id' 2>/dev/null); then
        log "WARNING: Failed to list versions of $package"
        return 0
    fi

    while IFS= read -r version_id; do
        [ -n "$version_id" ] || continue

        if gh api --method DELETE "$versions_api/$version_id" >/dev/null 2>&1; then
            log "Untagged ImageBuilder version removed: $version_id"
        else
            log "WARNING: Failed to remove untagged version: $version_id"
        fi
    done <<< "$stale_ids"
}

publish() {
    local profile=${1:?Usage: ImageBuilder.sh publish <Router|Cloud> <source-dir>}
    local source_dir=${2:?Usage: ImageBuilder.sh publish <Router|Cloud> <source-dir>}
    local archive
    local manifest
    local bundle_dir
    local ref

    require_profile "$profile"
    require_dir "$source_dir" "OpenWrt source directory"
    require_command oras
    require_command tar

    : "${WRT_HASH:?WRT_HASH is required}"
    : "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"

    archive=$(find "$source_dir/bin/targets" -type f -name '*-imagebuilder-*.tar.zst' | sort | head -1)
    manifest=$(find "$source_dir/bin/targets" -type f -name '*.manifest' | sort | head -1)

    require_file "$archive" "ImageBuilder archive"
    require_file "$manifest" "firmware manifest"

    make_workspace

    if ! tar --zstd -tf "$archive" > "$WORKSPACE/archive-files"; then
        log "ERROR: Invalid ImageBuilder archive"
        exit 1
    fi

    # The package is publicly readable: never let generated private settings leak.
    if grep -qF '99-custom-settings' "$WORKSPACE/archive-files"; then
        log "ERROR: ImageBuilder archive contains generated private settings"
        exit 1
    fi

    if [ -z "$(extract_packages "$manifest")" ]; then
        log "ERROR: No packages found in firmware manifest"
        exit 1
    fi

    bundle_dir="$WORKSPACE/bundle"
    mkdir -p "$bundle_dir"
    cp "$archive" "$bundle_dir/imagebuilder.tar.zst"
    cp "$manifest" "$bundle_dir/firmware.manifest"

    ref=$(package_ref "$profile")
    registry_login "$ref"

    # Build metadata rides on the manifest so restore can read it without
    # pulling the archive.
    (
        cd "$bundle_dir"
        oras push "$ref" \
            --artifact-type "$ARTIFACT_TYPE" \
            --annotation "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY}" \
            --annotation "org.opencontainers.image.revision=${GITHUB_SHA:-}" \
            --annotation "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
            --annotation "org.opencontainers.image.description=OpenWrt ImageBuilder baseline for $profile" \
            --annotation "openwrt.profile=$profile" \
            --annotation "openwrt.wrt-hash=$WRT_HASH" \
            --annotation "openwrt.wrt-commit=${WRT_COMMIT:-}" \
            --annotation "openwrt.wrt-branch=${WRT_BRANCH:-}" \
            --annotation "openwrt.build-date=${BUILD_DATE:-}" \
            --annotation "openwrt.run-id=$GITHUB_RUN_ID" \
            imagebuilder.tar.zst:application/zstd \
            firmware.manifest:text/plain
    )

    prune_untagged_versions "$ref"

    log "ImageBuilder published: $ref ($WRT_HASH)"
}

restore() {
    local profile=${1:?Usage: ImageBuilder.sh restore <Router|Cloud> <target-dir>}
    local target_dir=${2:?Usage: ImageBuilder.sh restore <Router|Cloud> <target-dir>}
    local manifest
    local bundle_dir
    local wrt_hash
    local ref
    local file

    require_profile "$profile"
    require_command oras
    require_command jq
    require_command tar

    case "$target_dir" in
        ""|/)
            log "ERROR: Unsafe ImageBuilder target directory: ${target_dir:-empty}"
            exit 1
            ;;
    esac

    mkdir -p "$target_dir"
    target_dir=$(cd "$target_dir" && pwd -P)

    make_workspace

    ref=$(package_ref "$profile")
    registry_login "$ref"

    # One manifest fetch answers three questions: does a baseline exist, does it
    # belong to this profile, and what was it built from.
    if ! manifest=$(oras manifest fetch "$ref" 2>"$WORKSPACE/registry-error.log"); then
        cat "$WORKSPACE/registry-error.log" >&2
        # Absent package on the first run, expired credentials, registry outage:
        # all get the same answer, because FullBuilder is always correct.
        unavailable "cannot fetch $ref"
    fi

    if ! printf '%s' "$manifest" | jq -e \
        --arg profile "$profile" \
        '.annotations["openwrt.profile"] == $profile' >/dev/null; then
        unavailable "profile mismatch for $ref"
    fi

    printf '%s' "$manifest" | jq '{
        profile: .annotations["openwrt.profile"],
        wrt_hash: .annotations["openwrt.wrt-hash"],
        wrt_commit: .annotations["openwrt.wrt-commit"],
        wrt_branch: .annotations["openwrt.wrt-branch"],
        build_date: .annotations["openwrt.build-date"],
        repository_commit: .annotations["org.opencontainers.image.revision"],
        github_run_id: .annotations["openwrt.run-id"]
    }' > "$WORKSPACE/metadata.json"

    wrt_hash=$(jq -r '.wrt_hash // empty' "$WORKSPACE/metadata.json")
    if [[ ! "$wrt_hash" =~ ^[0-9a-f]{40}$ ]]; then
        unavailable "invalid upstream hash for $ref"
    fi

    bundle_dir="$WORKSPACE/bundle"
    mkdir -p "$bundle_dir"

    # oras verifies every blob digest against the manifest while pulling.
    if ! oras pull "$ref" --output "$bundle_dir"; then
        log "ERROR: Failed to pull $ref"
        exit 1
    fi

    for file in imagebuilder.tar.zst firmware.manifest; do
        if [ ! -f "$bundle_dir/$file" ]; then
            unavailable "$file missing from $ref"
        fi
    done

    find "$target_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    if ! tar --zstd -xf "$bundle_dir/imagebuilder.tar.zst" -C "$target_dir" --strip-components=1; then
        log "ERROR: Failed to extract ImageBuilder archive"
        exit 1
    fi

    if [ ! -f "$target_dir/Makefile" ] || [ ! -d "$target_dir/packages" ]; then
        find "$target_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        unavailable "invalid ImageBuilder archive from $ref"
    fi

    extract_packages "$bundle_dir/firmware.manifest" > "$target_dir/.imagebuilder-packages"
    cp "$bundle_dir/firmware.manifest" "$target_dir/.imagebuilder-manifest"
    cp "$WORKSPACE/metadata.json" "$target_dir/.imagebuilder-metadata.json"

    log "ImageBuilder restored: $ref ($wrt_hash)"
}

usage() {
    printf "Usage: %s <publish|restore> <Router|Cloud> <dir>\n" "$0" >&2
}

main() {
    local action="${1:-}"
    shift || true

    case "$action" in
        publish)
            publish "$@"
            ;;
        restore)
            restore "$@"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
