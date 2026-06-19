#!/bin/bash -e

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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

copy_private_scripts() {
    local entry
    local source_path
    local dest_path
    local label
    local source_file

    for entry in "${PRIVATE_SCRIPT_COPIES[@]}"; do
        IFS='|' read -r source_path dest_path label <<< "$entry"
        [ -n "$source_path" ] || continue

        section "$label"
        log "Setting up $label"
        source_file=$(find "$REPO_TEMP_DIR" -path "*/$source_path" -print -quit 2>/dev/null || true)

        if [ -f "$source_file" ]; then
            mkdir -p "$(dirname "$dest_path")"
            cp "$source_file" "$dest_path"
            chmod +x "$dest_path"
        else
            log "Warning: $source_path not found, skipping $label"
        fi
    done
}

copy_argon_background() {
    local source_file

    if [ -z "$ARGON_BACKGROUND_SOURCE" ] || [ -z "$ARGON_BACKGROUND_DEST" ]; then
        return 0
    fi

    section "Argon Theme"
    log "Replacing Argon background image"
    source_file=$(find "$REPO_TEMP_DIR" -path "*/$ARGON_BACKGROUND_SOURCE" -print -quit 2>/dev/null || true)

    if [ -f "$source_file" ]; then
        if [ -d "$(dirname "$ARGON_BACKGROUND_DEST")" ]; then
            cp "$source_file" "$ARGON_BACKGROUND_DEST"
        else
            log "Warning: Argon theme directory not found, skipping background replacement"
        fi
    else
        log "Warning: $ARGON_BACKGROUND_SOURCE not found, skipping background replacement"
    fi
}

download_files() {
    local entry
    local url
    local dest_path

    if [ "${#FILE_DOWNLOADS[@]}" -eq 0 ]; then
        return 0
    fi

    section "Download Files"
    log "Downloading configured files"

    for entry in "${FILE_DOWNLOADS[@]}"; do
        IFS='|' read -r url dest_path <<< "$entry"
        [ -n "$url" ] && [ -n "$dest_path" ] || continue
        mkdir -p "$(dirname "$dest_path")"
        wget -q -O "$dest_path" "$url"
    done
}

download_nikki_ui() {
    local temp_dir

    if [ -z "$NIKKI_UI_URL" ] || [ -z "$NIKKI_UI_DEST" ]; then
        return 0
    fi

    section "Nikki Web UI"
    if [ -d "files/etc/nikki/run/ui" ]; then
        log "Removing existing nikki ui directory"
        rm -rf files/etc/nikki/run/ui
    fi

    log "Downloading Nikki zashboard UI"
    mkdir -p "$NIKKI_UI_DEST"
    temp_dir=$(mktemp -d)
    wget -q --no-show-progress -O "$temp_dir/dist.zip" "$NIKKI_UI_URL" 2>/dev/null
    unzip -qq "$temp_dir/dist.zip" -d "$temp_dir" 2>/dev/null
    find "$temp_dir" -mindepth 2 -exec cp -r {} "$NIKKI_UI_DEST"/ \; 2>/dev/null || cp -r "$temp_dir"/* "$NIKKI_UI_DEST"/
    rm -rf "$temp_dir"
}

download_private_repo
copy_profile_files
copy_argon_background
copy_private_scripts
download_files
download_nikki_ui

log "ApplyPrepare.sh completed"
