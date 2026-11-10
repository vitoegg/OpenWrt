#!/bin/bash

# Collects the files baked into the firmware: private config, rule sets and web UI

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"

load_profile "${1:?Usage: files.sh <Router|Cloud>}"
FILE_DOWNLOADS+=("https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/i915/tgl_guc_70.bin?h=$GUC_FIRMWARE_TAG|files/lib/firmware/i915/tgl_guc_70.bin")

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

download_file() {
    local url="$1"
    local dest_path="$2"

    wget -q --tries=3 --timeout=20 --waitretry=5 --retry-connrefused \
        --retry-on-http-error=429,500,502,503,504 -O "$dest_path" "$url" ||
        die "Failed to download ${dest_path##*/}"
    [ -s "$dest_path" ] || die "Empty downloaded file: ${dest_path##*/}"
}

download_private_repo() {
    section "Private Files"

    curl -s -S -f -L --retry 3 -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" \
        -o "$TEMP_DIR/repo.zip" 2>/dev/null ||
        die "Failed to download pre-configuration files"
    unzip -q "$TEMP_DIR/repo.zip" -d "$TEMP_DIR/repo"
}

copy_profile_files() {
    local source_dir

    mkdir -p files/etc

    for source_dir in "$TEMP_DIR"/repo/*/"$BUILD_PROFILE/files/etc"; do
        [ -d "$source_dir" ] || continue
        cp -a "$source_dir"/. files/etc/
        # The firmware banner comes from base-files, patched by patches.sh
        rm -f files/etc/banner
        log_ok "$BUILD_PROFILE/files/etc -> files/etc"
        return 0
    done

    log_warn "$BUILD_PROFILE/files/etc not found in the private repo, skipped"
}

copy_private_files() {
    local entry
    local source_path
    local dest_path
    local source_file

    for entry in "${PRIVATE_FILE_COPIES[@]}"; do
        IFS='|' read -r source_path dest_path <<< "$entry"
        source_file=$(find "$TEMP_DIR/repo" -path "*/$source_path" -print -quit)

        if [ -f "$source_file" ]; then
            mkdir -p "$(dirname "$dest_path")"
            cp "$source_file" "$dest_path"
            if [ "${dest_path##*.}" = "sh" ]; then
                chmod +x "$dest_path"
            fi
            log_ok "$source_path -> $dest_path"
        else
            log_warn "$source_path not found in the private repo, skipped"
        fi
    done
}

download_files() {
    local entry
    local url
    local dest_path

    section "Downloads"

    for entry in "${FILE_DOWNLOADS[@]}"; do
        IFS='|' read -r url dest_path <<< "$entry"

        mkdir -p "$(dirname "$dest_path")"
        download_file "$url" "$dest_path"
        log_ok "$dest_path ($(wc -c < "$dest_path" | tr -d '[:space:]') bytes)"
    done
}

download_nikki_ui() {
    if [ -z "$NIKKI_UI_URL" ] || [ -z "$NIKKI_UI_DEST" ]; then
        return 0
    fi

    section "Nikki Web UI"
    # Only the configured UI is shipped
    rm -rf "$(dirname "$NIKKI_UI_DEST")"
    mkdir -p "$NIKKI_UI_DEST"

    download_file "$NIKKI_UI_URL" "$TEMP_DIR/dist.zip"
    unzip -qq "$TEMP_DIR/dist.zip" -d "$TEMP_DIR/ui"
    cp -a "$TEMP_DIR/ui/dist"/. "$NIKKI_UI_DEST"/
    log_ok "$NIKKI_UI_DEST ($(find "$NIKKI_UI_DEST" -type f | wc -l | tr -d '[:space:]') files)"
}

download_private_repo
copy_profile_files
copy_private_files
download_files
download_nikki_ui
