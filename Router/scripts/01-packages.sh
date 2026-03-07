#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Remove built-in nikki (if exists)
for dir in feeds/packages/net/nikki feeds/luci/applications/luci-app-nikki; do
    if [ -d "$dir" ]; then
        log "Removing existing $dir"
        rm -rf "$dir"
    fi
done

# Nikki - add personalized package
log "Cloning personalized nikki repository"
git clone --depth=1 https://github.com/vitoegg/OpenNikki.git package/custom/OpenNikki

# Argon - add customized argon theme
if [ -d "feeds/luci/themes/luci-theme-argon" ]; then
    log "Removing existing argon theme"
    rm -rf feeds/luci/themes/luci-theme-argon
fi
log "Cloning customized argon theme"
git clone --depth=1 https://github.com/vitoegg/Argon package/custom/luci-theme-argon

log "01-packages.sh completed"
