#!/bin/bash -e

### Add new packages or patches below
### For example, download alist from a third-party repository to package/new/alist
### Then, add CONFIG_PACKAGE_luci-app-alist=y to the end of openwrt/23-config-common-custom

# Logging function
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg"
}

# lrzsz - add patched package
log "Adding patched lrzsz package"
rm -rf feeds/packages/utils/lrzsz
git clone https://$github/sbwml/packages_utils_lrzsz package/new/lrzsz

# Modify Argon theme
log "Switching to the original Argon"
rm -rf package/new/extd/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/app/luci-theme-argon
mv package/app/luci-theme-argon package/new/extd//luci-theme-argon
log "Modifying Argon background"
cp -f $GITHUB_WORKSPACE/files/Lite/bg1.jpg package/new/extd/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg
log "Modifying Argon footer"
sed -i '/<a class="luci-link".*Powered by/d' package/new/extd/luci-theme-argon/luasrc/view/themes/argon/footer.htm
sed -i '/<a class="luci-link".*Powered by/d; /distversion/d; /ArgonTheme <%# vPKG_VERSION %>/s/ \/ *$//' package/new/extd/luci-theme-argon/luasrc/view/themes/argon/footer_login.htm

# Set CPU Mode
log "Setting CPU mode to PERFORMANCE"
sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND is not set/g' target/linux/x86/config-6.11
sed -i 's/CONFIG_CPU_FREQ_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_GOV_ONDEMAND is not set/g' target/linux/x86/config-6.11
sed -i 's/# CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE is not set/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' target/linux/x86/config-6.11
sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' target/linux/x86/64/config-6.11
sed -i 's/CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_GOV_PERFORMANCE=y/g' target/linux/x86/64/config-6.11

log "Fixed AMD CPU Temperature"
cp -f $GITHUB_WORKSPACE/files/Lite/cpuinfo package/system/autocore/files/generic/cpuinfo

# Modify Hostname
log "Modifying hostname to HomeLab"
sed -i 's#OpenWrt#HomeLab#g' package/base-files/files/bin/config_generate

# Delete LED Menu
log "Removing LED menu from LuCI"
awk '
BEGIN { skip=0; brace_count=0; }
/[[:space:]]*"admin\/system\/leds": {/ { 
  skip=1; 
  brace_count=1; 
  next; 
}
{
  if(skip==1) {
    if($0 ~ /{/) brace_count++;
    if($0 ~ /}/) brace_count--;
    if(brace_count==0) {
      if($0 ~ /},/) {
        skip=0;
        next;
      } else if($0 ~ /}/) {
        skip=0;
        next;
      }
    }
  } else {
    print;
  }
}
' feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json > /tmp/temp.json && mv /tmp/temp.json feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json

# Default settings
log "Setting up network configuration"
ZZZ="package/new/default-settings/default/zzz-default-settings"
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
uci set dhcp.@dnsmasq[0].cachesize="0"
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5533'
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

# Enable Shortcut-FE
uci del firewall.cfg01e63d.flow_offloading
uci set firewall.cfg01e63d.shortcut_fe='1'
uci set firewall.cfg01e63d.shortcut_fe_module='shortcut-fe-cm'
uci commit firewall
EOF
sed -i '/exit 0/d' $ZZZ && echo "exit 0" >> $ZZZ

# Move configuration files
log "Removing sysctl.d and creating tmp directory"
rm -rf files/etc/sysctl.d
mkdir -p /tmp/repo_download
log "Downloading pre-configuration files"
curl -s -S -f -L -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" -o /tmp/repo_download/repo.zip 2>/dev/null
unzip -q /tmp/repo_download/repo.zip -d /tmp/repo_download/
log "Setting up pre-configuration files"
mv /tmp/repo_download/*/Lite/files/etc/* files/etc/
rm -rf /tmp/repo_download

# Add Services Update Script
log "Adding services update script"
mkdir -p files/usr/share/task
wget -qO- $UPDATE_SH_URL > files/usr/share/task/update_services.sh
chmod +x files/usr/share/task/update_services.sh
# Add Cron Job
mkdir -p files/etc/crontabs
echo "0 5 * * 6 /usr/share/task/update_services.sh" >> files/etc/crontabs/root

# Pre-downloading MosDNS rules
log "Pre-downloading MosDNS rules"
mkdir -p files/etc/mosdns/rule
MOSDNS_RULE_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Apple/Service.txt"
wget -qO- $MOSDNS_RULE_URL > files/etc/mosdns/rule/apple.txt

log "Pre-downloading zashboard UI"
mkdir -p files/etc/nikki/run/ui/zashboard
ZASHBOARD_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip"
TEMP_DIR=$(mktemp -d)
wget -qO "$TEMP_DIR/dist.zip" $ZASHBOARD_URL && unzip -q "$TEMP_DIR/dist.zip" -d "$TEMP_DIR"
cp -r "$TEMP_DIR/dist"/* files/etc/nikki/run/ui/zashboard/ && rm -rf "$TEMP_DIR"

log "Pre-downloading AdGuardHome core"
mkdir -p files/usr/bin/AdGuardHome
ADGUARDHOME_CORE_URL="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_amd64.tar.gz"
wget -qO- $ADGUARDHOME_CORE_URL | tar xOz > files/usr/bin/AdGuardHome/AdGuardHome
chmod +x files/usr/bin/AdGuardHome/AdGuardHome

log "Pre-downloading AdGuardHome filters"
mkdir -p files/usr/bin/AdGuardHome/data/filters
ADGUARDHOME_FILTER1_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/AdGuard/customized.txt"
ADGUARDHOME_FILTER2_URL="https://raw.githubusercontent.com/miaoermua/AdguardFilter/main/rule.txt"
ADGUARDHOME_FILTER3_URL="https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/AWAvenue-Ads-Rule.txt"
wget -qO- $ADGUARDHOME_FILTER1_URL > files/usr/bin/AdGuardHome/data/filters/1.txt &
wget -qO- $ADGUARDHOME_FILTER2_URL > files/usr/bin/AdGuardHome/data/filters/2.txt &
wget -qO- $ADGUARDHOME_FILTER3_URL > files/usr/bin/AdGuardHome/data/filters/3.txt &
wait

log "Script completed successfully"
