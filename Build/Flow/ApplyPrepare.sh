#!/bin/bash -e

source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

load_profile "${1:?Usage: ApplyPrepare.sh <Router|Cloud>}"

REPO_TEMP_DIR=""

cleanup_private_repo() {
    if [ -n "$REPO_TEMP_DIR" ]; then
        rm -rf "$REPO_TEMP_DIR"
    fi
}

trap cleanup_private_repo EXIT

download_private_repo() {
    section "Config Files"

    log "Downloading pre-configuration files"
    REPO_TEMP_DIR=$(mktemp -d)
    curl -s -S -f -L -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" -o "$REPO_TEMP_DIR/repo.zip" 2>/dev/null
    unzip -q "$REPO_TEMP_DIR/repo.zip" -d "$REPO_TEMP_DIR/"
}

copy_profile_files() {
    local source_dir

    log "Setting up pre-configuration files"
    mkdir -p files/etc

    for source_dir in "$REPO_TEMP_DIR"/*/"$BUILD_PROFILE/files/etc"; do
        if [ -d "$source_dir" ]; then
            cp -a "$source_dir"/. files/etc/
            return 0
        fi
    done

    log "Warning: ${BUILD_PROFILE}/files/etc not found, skipping pre-configuration files"
}

copy_private_files() {
    local entry
    local source_path
    local dest_path
    local label
    local source_file

    for entry in "${PRIVATE_FILE_COPIES[@]}"; do
        IFS='|' read -r source_path dest_path label <<< "$entry"
        [ -n "$source_path" ] || continue

        section "$label"
        log "Setting up $label"
        source_file=$(find "$REPO_TEMP_DIR" -path "*/$source_path" -print -quit 2>/dev/null || true)

        if [ -f "$source_file" ]; then
            mkdir -p "$(dirname "$dest_path")"
            cp "$source_file" "$dest_path"
            if [ "${dest_path##*.}" = "sh" ]; then
                chmod +x "$dest_path"
            fi
        else
            log "Warning: $source_path not found, skipping $label"
        fi
    done
}

download_files() {
    local entry
    local url
    local dest_path
    local file_name
    local dest_dir
    local tmp_path
    local bytes

    if [ "${#FILE_DOWNLOADS[@]}" -eq 0 ]; then
        return 0
    fi

    section "Download Files"
    log "Downloading configured files"

    for entry in "${FILE_DOWNLOADS[@]}"; do
        IFS='|' read -r url dest_path <<< "$entry"
        [ -n "$url" ] && [ -n "$dest_path" ] || continue
        file_name=${dest_path##*/}
        dest_dir=$(dirname "$dest_path")
        mkdir -p "$dest_dir"
        tmp_path=$(mktemp "$dest_dir/.${file_name}.XXXXXX")

        log "Downloading $file_name"
        if ! wget -q --tries=3 --timeout=20 --waitretry=5 --retry-connrefused \
            --retry-on-http-error=429,500,502,503,504 -O "$tmp_path" "$url"; then
            rm -f "$tmp_path"
            log "ERROR: Failed to download $file_name"
            return 1
        fi

        if [ ! -s "$tmp_path" ]; then
            rm -f "$tmp_path"
            log "ERROR: Empty downloaded file: $file_name"
            return 1
        fi

        bytes=$(wc -c < "$tmp_path")
        bytes=$(trim "$bytes")
        mv "$tmp_path" "$dest_path"
        log "Downloaded $file_name (${bytes} bytes)"
    done
}

download_nikki_ui() {
    local temp_dir

    if [ -z "$NIKKI_UI_URL" ] || [ -z "$NIKKI_UI_DEST" ]; then
        return 0
    fi

    section "Nikki Web UI"
    rm -rf files/etc/nikki/run/ui
    mkdir -p "$NIKKI_UI_DEST"

    log "Downloading Nikki zashboard UI"
    temp_dir=$(mktemp -d)
    wget -q --no-show-progress -O "$temp_dir/dist.zip" "$NIKKI_UI_URL"
    unzip -qq "$temp_dir/dist.zip" -d "$temp_dir"
    cp -a "$temp_dir/dist"/. "$NIKKI_UI_DEST"/
    rm -rf "$temp_dir"
}

download_private_repo
copy_profile_files
copy_private_files
download_files
download_nikki_ui

log "ApplyPrepare.sh completed"
