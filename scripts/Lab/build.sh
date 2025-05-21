#!/bin/bash
#=================================================
# Description: DIY script
# License: MIT
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
log "Removing existing packages"
rm -rf feeds/packages/net/mosdns || log "Failed to remove mosdns"
rm -rf feeds/luci/applications/luci-app-mosdns || log "Failed to remove luci-app-mosdns"
rm -rf feeds/packages/net/v2ray-geodata || log "Failed to remove v2ray-geodata"
rm -rf feeds/luci/applications/luci-app-openclash || log "Failed to remove luci-app-openclash"
rm -rf feeds/luci/themes/luci-theme-argon || log "Failed to remove luci-theme-argon"

# Add new packages
log "Adding new packages"
git clone --depth=1 https://github.com/vernesong/OpenClash package/app/luci-openclash || log "Failed to clone OpenClash"
git clone --depth=1 https://github.com/rufengsuixing/luci-app-adguardhome package/app/luci-adguardhome || log "Failed to clone AdGuardHome"
git clone --depth=1 https://github.com/sbwml/luci-app-mosdns package/app/luci-mosdns || log "Failed to clone MosDNS"
git clone --depth=1 https://github.com/sbwml/v2ray-geodata package/geo/v2ray-geodata || log "Failed to clone v2ray-geodata"
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/app/luci-theme-argon || log "Failed to clone Argon theme"

# Modify OpenClash
log "Modifying OpenClash config"
sed -i 's/dashboard_password="[^"]*"/dashboard_password="$DASHBOARD_PASSWORD"/g' package/app/luci-openclash/luci-app-openclash/root/etc/uci-defaults/luci-openclash || log "Failed to modify OpenClash password"
rm -rf package/app/luci-openclash/luci-app-openclash/root/etc/openclash/game_rules/* || log "Failed to remove OpenClash game rules"
find package/app/luci-openclash/luci-app-openclash/root/etc/openclash/rule_provider -type f ! -name "*.yaml" -exec rm -f {} + || log "Failed to remove OpenClash rule provider files"

# Modify Argon theme
log "Modifying Argon theme"
mv package/app/luci-theme-argon feeds/luci/themes/luci-theme-argon || log "Failed to move Argon theme"
cp -f $GITHUB_WORKSPACE/files/Router/bg1.jpg feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg || log "Failed to replace Argon background"
sed -i '/<a class="luci-link".*Powered by/d' feeds/luci/themes/luci-theme-argon/luasrc/view/themes/argon/footer.htm || log "Failed to modify Argon footer"
sed -i '/<a class="luci-link".*Powered by/d; /distversion/d; /ArgonTheme <%# vPKG_VERSION %>/s/ \/ *$//' feeds/luci/themes/luci-theme-argon/luasrc/view/themes/argon/footer_login.htm || log "Failed to modify Argon login footer"


# LUCI configuration
log "Applying LuCI configuration"
NET="package/base-files/files/bin/config_generate"
sed -i 's#192.168.1.1#192.168.10.1#g' $NET || log "Failed to modify login IP"
sed -i 's#ImmortalWrt#HomeLab#g' $NET || log "Failed to modify Hostname"

# Network configuration
log "Applying Network configuration"
cat >> $ZZZ <<-EOF
# Set Password
sed -i 's|root:::0:99999:7:::|root:$ROOT_PASSWORD_HASH:20211:0:99999:7:::|g' /etc/shadow

# Set PPPOE Dial-up
uci set network.wan.proto='pppoe'
uci set network.wan.username='$PPPOE_USERNAME'
uci set network.wan.password='$PPPOE_PASSWORD'
uci set network.wan.delegate='0'
uci delete network.globals.ula_prefix
uci delete network.wan6
uci commit network
# Set PPPOE Device
uci add network device # =cfg060f15
uci set network.cfg060f15.macaddr='$PPPOE_MAC'
uci set network.@device[-1].name='pppoe-wan'
uci set network.@device[-1].ipv6='0'
uci commit network
# Disable IPv6
uci set network.lan.ip6assign=''
uci set network.wan.ipv6='0'
uci set network.wan.sourcefilter='0'
uci set network.lan.delegate='0'
uci set network.wan.delegate='0'
uci commit network
uci set dhcp.lan.ra=''
uci set dhcp.lan.dhcpv6=''
uci set dhcp.lan.ra_management=''
uci set dhcp.@dnsmasq[0].filter_aaaa='1'
uci set dhcp.@dnsmasq[0].cachesize="1000"
uci commit dhcp
# Set Static DHCP
uci add dhcp host #1
uci set dhcp.@host[-1].name='Router'
uci set dhcp.@host[-1].mac='$ROUTER_MAC'
uci set dhcp.@host[-1].ip='192.168.10.3'
uci set dhcp.@host[-1].dns="1"
uci set dhcp.@host[-1].leasetime='infinite'
uci add dhcp host #2
uci set dhcp.@host[-1].name='LMini'
uci set dhcp.@host[-1].mac='$LMINI_MAC'
uci set dhcp.@host[-1].ip='192.168.10.5'
uci set dhcp.@host[-1].dns="1"
uci set dhcp.@host[-1].leasetime='infinite'
uci commit dhcp
EOF
sed -i '/exit 0/d' $ZZZ && echo "exit 0" >> $ZZZ  || log "Failed to Exit"

# Move configuration files
log "Creating files directory"
mkdir -p files/etc
mkdir -p /tmp/repo_download
log "Downloading configuration"
curl -s -S -f -L -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" -o /tmp/repo_download/repo.zip 2>/dev/null
unzip -q /tmp/repo_download/repo.zip -d /tmp/repo_download/
log "Move the configuration files..."
mv /tmp/repo_download/*/Router/files/etc/* files/etc/
log "Clean up the directory"
rm -rf /tmp/repo_download

# Pre-download necessary files
log "Pre-downloading openclash core"
mkdir -p files/etc/openclash/core
OPENCLASH_CORE_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64.tar.gz"
wget -qO- $OPENCLASH_CORE_URL | tar xOvz > files/etc/openclash/core/clash_meta
chmod +x files/etc/openclash/core/clash*

log "Pre-downloading adguardhome core"
mkdir -p files/usr/bin/AdGuardHome
ADGUARDHOME_CORE_URL="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_amd64.tar.gz"
wget -qO- $ADGUARDHOME_CORE_URL | tar xOvz > files/usr/bin/AdGuardHome/AdGuardHome
chmod +x files/usr/bin/AdGuardHome/AdGuardHome

log "Script completed successfully"