#!/bin/bash

# Publishes and restores the ImageBuilder baseline on GHCR

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/registry.sh"

ARTIFACT_TYPE='application/vnd.openwrt.imagebuilder.v1+tar+zstd'

# Exit status 2 tells the caller to fall back to a full build
die_unavailable() {
    log_warn "ImageBuilder unavailable: $1"
    exit 2
}

manifest_packages() {
    awk 'NF >= 3 && $2 == "-" {print $1}' "$1" | sort -u
}

missing_packages() {
    local manifest="$1"
    local profile="$2"

    config_packages "$profile" | comm -23 - <(manifest_packages "$manifest")
}

publish() {
    local profile=${1:?Usage: imagebuilder.sh publish <Router|Cloud> <source-dir>}
    local source_dir=${2:?Usage: imagebuilder.sh publish <Router|Cloud> <source-dir>}
    local archive
    local manifest
    local bundle_dir
    local ref
    local cutoff

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
        die "Invalid ImageBuilder archive"
    fi

    if grep -qF '99-custom-settings' "$WORKSPACE/archive-files"; then
        die "ImageBuilder archive contains generated private settings"
    fi

    if [ -z "$(manifest_packages "$manifest")" ]; then
        die "No packages found in firmware manifest"
    fi

    bundle_dir="$WORKSPACE/bundle"
    mkdir -p "$bundle_dir"
    cp "$archive" "$bundle_dir/imagebuilder.tar.zst"
    cp "$manifest" "$bundle_dir/firmware.manifest"

    if [ -f "$source_dir/.apps-baseline.json" ]; then
        cp "$source_dir/.apps-baseline.json" "$bundle_dir/apps.json"
    else
        printf '{}' > "$bundle_dir/apps.json"
        log_warn "No app baseline recorded, apps will never be refreshed"
    fi

    ref=$(package_ref "$profile")
    cutoff=$(registry_cutoff)
    registry_login "$ref"

    if ! (
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
            firmware.manifest:text/plain \
            apps.json:application/json
    ); then
        die "Failed to push $ref"
    fi

    prune_stale_versions "$ref" "$cutoff"

    log_ok "ImageBuilder published: $ref ($WRT_HASH)"
}

restore() {
    local profile=${1:?Usage: imagebuilder.sh restore <Router|Cloud> <target-dir>}
    local target_dir=${2:?Usage: imagebuilder.sh restore <Router|Cloud> <target-dir>}
    local manifest
    local bundle_dir
    local wrt_hash
    local ref
    local file
    local missing

    require_profile "$profile"
    require_command oras
    require_command jq
    require_command tar

    case "$target_dir" in
        ""|/)
            die "Unsafe ImageBuilder target directory: ${target_dir:-empty}"
            ;;
    esac

    mkdir -p "$target_dir"
    target_dir=$(cd "$target_dir" && pwd -P)

    make_workspace

    ref=$(package_ref "$profile")
    registry_login "$ref"

    if ! manifest=$(oras manifest fetch "$ref" 2>"$WORKSPACE/registry-error.log"); then
        cat "$WORKSPACE/registry-error.log" >&2
        die_unavailable "cannot fetch $ref"
    fi

    if ! printf '%s' "$manifest" | jq -e \
        --arg profile "$profile" \
        '.annotations["openwrt.profile"] == $profile' >/dev/null; then
        die_unavailable "profile mismatch for $ref"
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
        die_unavailable "invalid upstream hash for $ref"
    fi

    bundle_dir="$WORKSPACE/bundle"
    mkdir -p "$bundle_dir"

    if ! oras pull "$ref" --output "$bundle_dir" >/dev/null; then
        die "Failed to pull $ref"
    fi

    for file in imagebuilder.tar.zst firmware.manifest; do
        if [ ! -f "$bundle_dir/$file" ]; then
            die_unavailable "$file missing from $ref"
        fi
    done

    missing=$(missing_packages "$bundle_dir/firmware.manifest" "$profile")
    if [ -n "$missing" ]; then
        die_unavailable "packages not in $ref: $(printf '%s' "$missing" | paste -sd' ' -)"
    fi

    find "$target_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    if ! tar --zstd -xf "$bundle_dir/imagebuilder.tar.zst" -C "$target_dir" --strip-components=1; then
        die "Failed to extract ImageBuilder archive"
    fi

    if [ ! -f "$target_dir/Makefile" ] || [ ! -d "$target_dir/packages" ]; then
        find "$target_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        die_unavailable "invalid ImageBuilder archive from $ref"
    fi

    manifest_packages "$bundle_dir/firmware.manifest" > "$target_dir/.imagebuilder-packages"
    cp "$WORKSPACE/metadata.json" "$target_dir/.imagebuilder-metadata.json"

    if [ -f "$bundle_dir/apps.json" ]; then
        cp "$bundle_dir/apps.json" "$target_dir/.imagebuilder-apps.json"
    else
        printf '{}' > "$target_dir/.imagebuilder-apps.json"
    fi
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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
