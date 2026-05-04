#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

section() {
    echo ""
    echo "========== $1 =========="
}

section "Config Files"

log "Downloading pre-configuration files"
REPO_TEMP_DIR=$(mktemp -d)
curl -s -S -f -L -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" -o "$REPO_TEMP_DIR/repo.zip" 2>/dev/null
unzip -q "$REPO_TEMP_DIR/repo.zip" -d "$REPO_TEMP_DIR/"
log "Setting up pre-configuration files"
mkdir -p files/etc
mv "$REPO_TEMP_DIR"/*/Cloud/files/etc/* files/etc/

section "Argon Theme"

log "Replacing Argon background image"
ARGON_BG_SRC=$(find "$REPO_TEMP_DIR" -path '*/uFiles/bg1.webp' -print -quit 2>/dev/null || true)
ARGON_BG_DIR="package/custom/luci-theme-argon/htdocs/luci-static/argon/img"
ARGON_BG_DST="$ARGON_BG_DIR/bg1.webp"
if [ -f "$ARGON_BG_SRC" ]; then
    if [ -d "$ARGON_BG_DIR" ]; then
        cp "$ARGON_BG_SRC" "$ARGON_BG_DST"
    else
        log "Warning: Argon theme directory not found, skipping background replacement"
    fi
else
    log "Warning: uFiles/bg1.webp not found, skipping background replacement"
fi

section "DDNS Script"

log "Setting up DDNS script"
DDNS_SCRIPT_SRC=$(find "$REPO_TEMP_DIR" -path '*/uFiles/ddns.sh' -print -quit 2>/dev/null || true)
DDNS_SCRIPT_DST="files/usr/share/task/ddns.sh"
if [ -f "$DDNS_SCRIPT_SRC" ]; then
    mkdir -p "$(dirname "$DDNS_SCRIPT_DST")"
    cp "$DDNS_SCRIPT_SRC" "$DDNS_SCRIPT_DST"
    chmod +x "$DDNS_SCRIPT_DST"
else
    log "Warning: uFiles/ddns.sh not found, skipping DDNS script"
fi

rm -rf "$REPO_TEMP_DIR"

log "Prepare.sh completed"
