#!/bin/bash
#=================================================
# Description: DIY script
# Lisence: MIT
# Author: P3TERX
# Blog: https://p3terx.com
#=================================================

set -e

# Logging function
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg"
}

# Remove existing packages
log "Removing existing Argon theme"
rm -rf feeds/luci/themes/luci-theme-argon || log "Failed to remove luci-theme-argon"

# Add new packages
log "Adding original Argon theme"
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/app/luci-theme-argon || log "Failed to clone Argon theme"

# Modify Argon theme
log "Modifying Argon theme"
mv package/app/luci-theme-argon feeds/luci/themes/luci-theme-argon || log "Failed to move Argon theme"
cp -f $GITHUB_WORKSPACE/files/Cloud/bg1.jpg feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg || log "Failed to replace Argon background"
sed -i '/<a class="luci-link".*Powered by/d' feeds/luci/themes/luci-theme-argon/luasrc/view/themes/argon/footer.htm || log "Failed to modify Argon footer"
sed -i '/<a class="luci-link".*Powered by/d; /distversion/d; /ArgonTheme <%# vPKG_VERSION %>/s/ \/ *$//' feeds/luci/themes/luci-theme-argon/luasrc/view/themes/argon/footer_login.htm || log "Failed to modify Argon login footer"

# Modify Samba4 Menu
log "Modifying Samba4 Menu"
sed -i 's/services/nas/g' feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json

# Modify Homepage Display
log "Modifying Model"
sed -i 's@head -n 1)@head -n 1 | awk -F "/" '"'"'{print $1}'"'"')@g' package/lean/autocore/files/x86/autocore || log "Failed to modify Model Name"
sed -i 's/${g}.*/${g}/g' package/lean/autocore/files/x86/autocore || log "Failed to modify Model"
log "Modifying CPU Info"
cp -f $GITHUB_WORKSPACE/files/Router/cpuinfo package/lean/autocore/files/x86/sbin/cpuinfo || log "Failed to Modify CPU Info"

# Set CPU Mode
log "Setting CPU mode to PERFORMANCE"
sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND is not set/g' target/linux/x86/config-5.15 || log "Failed to cancel FREQ_DEFAULT_GOV_ONDEMAND"
sed -i 's/CONFIG_CPU_FREQ_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_GOV_ONDEMAND is not set/g' target/linux/x86/config-5.15 || log "Failed to cancel FREQ_GOV_ONDEMAND"
sed -i 's/# CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE is not set/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' target/linux/x86/config-5.15 || log "Failed to set FREQ_DEFAULT_GOV_PERFORMANCE"
sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' target/linux/x86/64/config-5.15 || log "Failed to cancel SCHEDUTIL"
sed -i 's/CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_GOV_PERFORMANCE=y/g' target/linux/x86/64/config-5.15 || log "Failed to set GOV_PERFORMANCE"

# LUCI configuration
log "Applying LuCI configuration"
NET="package/base-files/luci2/bin/config_generate"
ZZZ="package/lean/default-settings/files/zzz-default-settings"
VERSION=$(grep DISTRIB_REVISION= $ZZZ | awk -F "'" '{print $2}')

sed -i 's#192.168.1.1#192.168.10.2#g' $NET || log "Failed to modify login IP"
sed -i "s|V4UetPzk\$CYXluq4wUazHjmCDBCqXF\.|$ROOT_PASSWORD_LEAN|g" $ZZZ || log "Failed to modify login Password"
sed -i 's#LEDE#HomeCloud#g' $NET || log "Failed to modify Hostname"
sed -i "s/LEDE/CLOUD/g" $ZZZ || log "Failed to modify Distname"
sed -i "s/${VERSION}/V$(TZ=UTC-8 date +"%y.%m.%d")/g" $ZZZ || log "Failed to modify Version"
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-light/Makefile || log "Failed to modify default Theme"
sed -i 's/os.date()/os.date("%Y.%m.%d %a %H:%M:%S")/g' package/lean/autocore/files/*/index.htm || log "Failed to modify Time format"
sed -i 's/KERNEL_PATCHVER:=6.6/KERNEL_PATCHVER:=5.15/g' target/linux/x86/Makefile || log "Failed to modify KERNEL"

# Exit Edit
sed -i '/exit 0/d' $ZZZ && echo "exit 0" >> $ZZZ  || log "Failed to Exit"

# Move configuration files
log "Creating files directory"
mkdir -p files/etc
mkdir -p /tmp/repo_download
log "Downloading configuration"
curl -s -S -f -L -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" -o /tmp/repo_download/repo.zip 2>/dev/null
unzip -q /tmp/repo_download/repo.zip -d /tmp/repo_download/
log "Move the configuration files..."
mv /tmp/repo_download/*/Cloud/files/etc/* files/etc/
log "Clean up the directory"
rm -rf /tmp/repo_download

log "Script completed successfully"