#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# ===== Download Pre-configuration Files from Private Repository =====

log "Downloading pre-configuration files"
REPO_TEMP_DIR=$(mktemp -d)
curl -s -S -f -L -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" -o "$REPO_TEMP_DIR/repo.zip" 2>/dev/null
unzip -q "$REPO_TEMP_DIR/repo.zip" -d "$REPO_TEMP_DIR/"
log "Setting up pre-configuration files"
mkdir -p files/etc
mv "$REPO_TEMP_DIR"/*/Lite/files/etc/* files/etc/
rm -rf "$REPO_TEMP_DIR"

# ===== Pre-download MosDNS Rules =====

log "Pre-downloading MosDNS rules"
mkdir -p files/etc/mosdns/rule
MOSDNS_APPLE_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/apple.txt"
MOSDNS_REJECT_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/reject.txt"
wget -qO- $MOSDNS_APPLE_URL > files/etc/mosdns/rule/apple.txt &
wget -qO- $MOSDNS_REJECT_URL > files/etc/mosdns/rule/reject.txt &
wait

# ===== Pre-download Nikki Zashboard UI =====

if [ -d "files/etc/nikki/run/ui" ]; then
    log "Removing existing nikki ui directory"
    rm -rf files/etc/nikki/run/ui
fi
log "Downloading Nikki zashboard UI"
mkdir -p files/etc/nikki/run/ui/zashboard
ZASHBOARD_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip"
TEMP_DIR=$(mktemp -d)
wget -q --no-show-progress -O "$TEMP_DIR/dist.zip" "$ZASHBOARD_URL" 2>/dev/null
unzip -qq "$TEMP_DIR/dist.zip" -d "$TEMP_DIR" 2>/dev/null
find "$TEMP_DIR" -mindepth 2 -exec cp -r {} files/etc/nikki/run/ui/zashboard/ \; 2>/dev/null || cp -r "$TEMP_DIR"/* files/etc/nikki/run/ui/zashboard/
rm -rf "$TEMP_DIR"

log "Prepare.sh completed"
