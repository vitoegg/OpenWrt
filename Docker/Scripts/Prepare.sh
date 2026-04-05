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
mv "$REPO_TEMP_DIR"/*/Cloud/files/etc/* files/etc/
rm -rf "$REPO_TEMP_DIR"

# Add docker restart task to crontabs
log "Adding docker restart task to crontabs"
mkdir -p files/etc/crontabs
echo "15 5 * * * docker restart tunnel" >> files/etc/crontabs/root

# Download ddns script
log "Downloading ddns script"
mkdir -p files/usr/share/task
wget -qO- $DDNS_SH_URL > files/usr/share/task/ddns.sh
chmod +x files/usr/share/task/ddns.sh
log "Adding ddns script to crontabs"
echo "*/30 * * * * /usr/share/task/ddns.sh > /dev/null 2>&1" >> files/etc/crontabs/root

log "Prepare.sh completed"
