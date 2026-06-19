#!/bin/bash -e

source "$(dirname "${BASH_SOURCE[0]}")/../Flow/lib.sh"

BUILD_PROFILE=${1:?Usage: RestoreImageBuilder.sh <Router|Cloud> <target-dir>}
TARGET_DIR=${2:?Usage: RestoreImageBuilder.sh <Router|Cloud> <target-dir>}
REMOTE_ROOT=${IMAGEBUILDER_REMOTE_ROOT:-remote:/ImageBuilder}
REMOTE_ROOT=${REMOTE_ROOT%/}
TEMP_DIR=""

cleanup_restore() {
    if [ -n "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

baseline_unavailable() {
    log "ImageBuilder unavailable: $1"
    cleanup_restore
    trap - EXIT
    exit 2
}

is_missing_status() {
    case "$1" in
        3|4)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

case "$BUILD_PROFILE" in
    Router|Cloud)
        ;;
    *)
        log "ERROR: Unsupported build profile: $BUILD_PROFILE"
        exit 1
        ;;
esac

case "$TARGET_DIR" in
    ""|/)
        log "ERROR: Unsafe ImageBuilder target directory: ${TARGET_DIR:-empty}"
        exit 1
        ;;
esac

mkdir -p "$TARGET_DIR"
TARGET_DIR=$(cd "$TARGET_DIR" && pwd -P)

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

TEMP_DIR=$(mktemp -d)
trap cleanup_restore EXIT

profile_remote="$REMOTE_ROOT/$BUILD_PROFILE"
error_file="$TEMP_DIR/rclone-error.log"

set +e
base_id=$(rclone cat "$profile_remote/current" 2>"$error_file")
rclone_status=$?
set -e

if [ "$rclone_status" -ne 0 ]; then
    if is_missing_status "$rclone_status"; then
        baseline_unavailable "$profile_remote/current not found"
    fi
    cat "$error_file" >&2
    [ "$rclone_status" -ne 2 ] || rclone_status=1
    exit "$rclone_status"
fi

base_id=$(printf '%s' "$base_id" | tr -d '\r\n')
if [[ ! "$base_id" =~ ^[0-9a-f]{12}-[0-9]+$ ]]; then
    baseline_unavailable "invalid current base id"
fi

bundle_dir="$TEMP_DIR/bundle"
mkdir -p "$bundle_dir"

set +e
rclone copy "$profile_remote/$base_id" "$bundle_dir" --transfers=1
rclone_status=$?
set -e

if [ "$rclone_status" -ne 0 ]; then
    if is_missing_status "$rclone_status"; then
        baseline_unavailable "$profile_remote/$base_id not found"
    fi
    [ "$rclone_status" -ne 2 ] || rclone_status=1
    exit "$rclone_status"
fi

for file in imagebuilder.tar.zst packages.list firmware.manifest metadata.json SHA256SUMS; do
    if [ ! -f "$bundle_dir/$file" ]; then
        baseline_unavailable "$file missing from $base_id"
    fi
done

if ! (cd "$bundle_dir" && sha256sum -c SHA256SUMS); then
    baseline_unavailable "checksum verification failed for $base_id"
fi

if ! jq -e \
    --arg profile "$BUILD_PROFILE" \
    --arg base_id "$base_id" \
    '.profile == $profile and .base_id == $base_id' \
    "$bundle_dir/metadata.json" >/dev/null; then
    baseline_unavailable "metadata mismatch for $base_id"
fi

find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
if ! tar --zstd -xf "$bundle_dir/imagebuilder.tar.zst" -C "$TARGET_DIR" --strip-components=1; then
    log "ERROR: Failed to extract ImageBuilder archive"
    exit 1
fi

if [ ! -f "$TARGET_DIR/Makefile" ] || [ ! -d "$TARGET_DIR/packages" ]; then
    find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    baseline_unavailable "invalid ImageBuilder archive for $base_id"
fi

cp "$bundle_dir/packages.list" "$TARGET_DIR/.imagebuilder-packages"
cp "$bundle_dir/firmware.manifest" "$TARGET_DIR/.imagebuilder-manifest"
cp "$bundle_dir/metadata.json" "$TARGET_DIR/.imagebuilder-metadata.json"

log "ImageBuilder restored: $BUILD_PROFILE/$base_id"
