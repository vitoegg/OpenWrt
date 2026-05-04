#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

section() {
    echo ""
    echo "========== $1 =========="
}

# ===== Download Pre-configuration Files from Private Repository =====

section "Config Files"
log "Downloading pre-configuration files"
REPO_TEMP_DIR=$(mktemp -d)
curl -s -S -f -L -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" -o "$REPO_TEMP_DIR/repo.zip" 2>/dev/null
unzip -q "$REPO_TEMP_DIR/repo.zip" -d "$REPO_TEMP_DIR/"
log "Setting up pre-configuration files"
mkdir -p files/etc
mv "$REPO_TEMP_DIR"/*/Lite/files/etc/* files/etc/

section "MosDNS Update Script"
log "Setting up MosDNS rules update script"
MOSDNS_UPDATE_SCRIPT_SRC=$(find "$REPO_TEMP_DIR" -path '*/uFiles/update_mosdns_rules.sh' -print -quit 2>/dev/null || true)
MOSDNS_UPDATE_SCRIPT_DST="files/usr/share/task/update_mosdns_rules.sh"
if [ -f "$MOSDNS_UPDATE_SCRIPT_SRC" ]; then
    mkdir -p "$(dirname "$MOSDNS_UPDATE_SCRIPT_DST")"
    cp "$MOSDNS_UPDATE_SCRIPT_SRC" "$MOSDNS_UPDATE_SCRIPT_DST"
    chmod +x "$MOSDNS_UPDATE_SCRIPT_DST"
else
    log "Warning: uFiles/update_mosdns_rules.sh not found, skipping MosDNS rules update script"
fi

rm -rf "$REPO_TEMP_DIR"

# ===== Pre-download MosDNS Rules =====

section "MosDNS Rule Files"
log "Pre-downloading MosDNS rules"
mkdir -p files/etc/mosdns/rule
MOSDNS_GEOIP_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/geoip.txt"
MODNS_REJECT_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/reject.txt"
MOSDNS_APPLE_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/apple.txt"
MOSDNS_DIRECT_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/direct.txt"
MOSDNS_CHINA_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/china.txt"
MOSDNS_FOREIGN_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/foreign.txt"
wget -q -O files/etc/mosdns/rule/geoip.txt "$MOSDNS_GEOIP_URL"
wget -q -O files/etc/mosdns/rule/reject.txt "$MODNS_REJECT_URL"
wget -q -O files/etc/mosdns/rule/apple.txt "$MOSDNS_APPLE_URL"
wget -q -O files/etc/mosdns/rule/direct.txt "$MOSDNS_DIRECT_URL"
wget -q -O files/etc/mosdns/rule/china.txt "$MOSDNS_CHINA_URL"
wget -q -O files/etc/mosdns/rule/foreign.txt "$MOSDNS_FOREIGN_URL"

# ===== Pre-download Nikki Zashboard UI =====

section "Nikki Web UI"
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
