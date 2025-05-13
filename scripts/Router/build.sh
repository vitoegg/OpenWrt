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

# Modify Homepage Display
log "Modifying Model"
sed -i 's@head -n 1)@head -n 1 | awk -F "/" '"'"'{print $1}'"'"')@g' package/lean/autocore/files/x86/autocore || log "Failed to modify Model Name"
sed -i 's/${g}.*/${g}/g' package/lean/autocore/files/x86/autocore || log "Failed to modify Model Display"
log "Modifying CPU Info"
cp -f $GITHUB_WORKSPACE/files/Router/cpuinfo package/lean/autocore/files/x86/sbin/cpuinfo || log "Failed to Modify CPU Info"

# Remove IPv6 support
log "Removing IPv6 support"
sed -i 's/luci-proto-ipv6 //g' include/target.mk || log "Failed to modify target.mk"
sed -i '/\+IPV6:luci-proto-ipv6/d' feeds/luci/collections/luci-light/Makefile || log "Failed to modify luci-light Makefile"
sed -i 's/\+IPV6:luci-proto-ipv6 //g' feeds/luci/collections/luci-nginx/Makefile feeds/luci/collections/luci-ssl-nginx/Makefile || log "Failed to modify luci-nginx Makefile"

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

sed -i 's#192.168.1.1#192.168.10.1#g' $NET || log "Failed to modify login IP"
sed -i "s|V4UetPzk\$CYXluq4wUazHjmCDBCqXF\.|$ROOT_PASSWORD_LEAN|g" $ZZZ || log "Failed to modify login Password"
sed -i 's#LEDE#HomeLab#g' $NET || log "Failed to modify Hostname"
sed -i "s/LEDE/ROUTER/g" $ZZZ || log "Failed to modify Distname"
sed -i "s/${VERSION}/V$(TZ=UTC-8 date +"%y.%m.%d")/g" $ZZZ || log "Failed to modify Version"
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci-light/Makefile || log "Failed to modify default Theme"
sed -i 's/os.date()/os.date("%Y.%m.%d %a %H:%M:%S")/g' package/lean/autocore/files/*/index.htm || log "Failed to modify Time format"
sed -i 's/KERNEL_PATCHVER:=6.6/KERNEL_PATCHVER:=5.15/g' target/linux/x86/Makefile || log "Failed to modify KERNEL"

# Network configuration
log "Applying Network configuration"
cat >> $ZZZ <<-EOF
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
# Set TurboACC Configuration
uci set turboacc.global.set='1'
uci set turboacc.config.fastpath='flow_offloading'
uci set turboacc.config.fastpath_fo_hw='0'
uci set turboacc.config.fullcone='2'
uci set turboacc.config.tcpcca='bbr'
uci commit turboacc
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