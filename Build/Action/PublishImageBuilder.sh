#!/bin/bash

set -e

source "$(dirname "${BASH_SOURCE[0]}")/../Flow/lib.sh"

BUILD_PROFILE=${1:?Usage: PublishImageBuilder.sh <Router|Cloud> <source-dir>}
SOURCE_DIR=${2:?Usage: PublishImageBuilder.sh <Router|Cloud> <source-dir>}
REMOTE_ROOT=${IMAGEBUILDER_REMOTE_ROOT:-remote:/ImageBuilder}
REMOTE_ROOT=${REMOTE_ROOT%/}
TEMP_DIR=""

cleanup_publish() {
    if [ -n "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

case "$BUILD_PROFILE" in
    Router|Cloud)
        ;;
    *)
        log "ERROR: Unsupported build profile: $BUILD_PROFILE"
        exit 1
        ;;
esac

require_dir "$SOURCE_DIR" "OpenWrt source directory"
command -v rclone >/dev/null || {
    log "ERROR: rclone not found"
    exit 1
}
command -v jq >/dev/null || {
    log "ERROR: jq not found"
    exit 1
}
command -v sha256sum >/dev/null || {
    log "ERROR: sha256sum not found"
    exit 1
}
command -v tar >/dev/null || {
    log "ERROR: tar not found"
    exit 1
}

: "${WRT_HASH:?WRT_HASH is required}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"

imagebuilder_archive=$(find "$SOURCE_DIR/bin/targets" -type f -name '*-imagebuilder-*.tar.zst' | sort | head -1)
firmware_manifest=$(find "$SOURCE_DIR/bin/targets" -type f -name '*.manifest' | sort | head -1)

require_file "$imagebuilder_archive" "ImageBuilder archive"
require_file "$firmware_manifest" "firmware manifest"

TEMP_DIR=$(mktemp -d)
trap cleanup_publish EXIT

if ! tar --zstd -tf "$imagebuilder_archive" > "$TEMP_DIR/imagebuilder-files"; then
    log "ERROR: Invalid ImageBuilder archive"
    exit 1
fi

if grep -qF '99-custom-settings' "$TEMP_DIR/imagebuilder-files"; then
    log "ERROR: ImageBuilder archive contains generated private settings"
    exit 1
fi

base_id="${WRT_HASH:0:12}-${GITHUB_RUN_ID}"
profile_remote="$REMOTE_ROOT/$BUILD_PROFILE"
base_remote="$profile_remote/$base_id"

bundle_dir="$TEMP_DIR/bundle"
mkdir -p "$bundle_dir"

cp "$imagebuilder_archive" "$bundle_dir/imagebuilder.tar.zst"
cp "$firmware_manifest" "$bundle_dir/firmware.manifest"
awk 'NF >= 3 && $2 == "-" {print $1}' "$firmware_manifest" | sort -u > "$bundle_dir/packages.list"

if [ ! -s "$bundle_dir/packages.list" ]; then
    log "ERROR: No packages found in firmware manifest"
    exit 1
fi

jq -n \
    --arg base_id "$base_id" \
    --arg profile "$BUILD_PROFILE" \
    --arg wrt_hash "$WRT_HASH" \
    --arg wrt_commit "${WRT_COMMIT:-}" \
    --arg wrt_branch "${WRT_BRANCH:-}" \
    --arg build_date "${BUILD_DATE:-}" \
    --arg repository_commit "${GITHUB_SHA:-}" \
    --arg github_run_id "$GITHUB_RUN_ID" \
    '{
        base_id: $base_id,
        profile: $profile,
        wrt_hash: $wrt_hash,
        wrt_commit: $wrt_commit,
        wrt_branch: $wrt_branch,
        build_date: $build_date,
        repository_commit: $repository_commit,
        github_run_id: $github_run_id
    }' > "$bundle_dir/metadata.json"

(
    cd "$bundle_dir"
    sha256sum imagebuilder.tar.zst packages.list firmware.manifest metadata.json > SHA256SUMS
)

rclone mkdir "$profile_remote"
rclone mkdir "$base_remote"
rclone copy "$bundle_dir" "$base_remote" --transfers=1 --stats-one-line --stats=20s

printf '%s\n' "$base_id" > "$TEMP_DIR/current"
rclone copyto "$TEMP_DIR/current" "$profile_remote/current"

if stale_dirs=$(rclone lsf "$profile_remote" --dirs-only); then
    while IFS= read -r stale_dir; do
        stale_id=${stale_dir%/}
        [[ "$stale_id" =~ ^[0-9a-f]{12}-[0-9]+$ ]] || continue
        [ "$stale_id" != "$base_id" ] || continue

        if rclone purge "$profile_remote/$stale_id"; then
            log "Old ImageBuilder removed: $BUILD_PROFILE/$stale_id"
        else
            log "WARNING: Failed to remove old ImageBuilder: $BUILD_PROFILE/$stale_id"
        fi
    done <<< "$stale_dirs"
else
    log "WARNING: Failed to list old ImageBuilder bundles for $BUILD_PROFILE"
fi

log "ImageBuilder published: $BUILD_PROFILE/$base_id"
