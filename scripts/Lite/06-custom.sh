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
sed -i '/<a class="luci-link".*Powered by/,+2d' package/new/extd/luci-theme-argon/luasrc/view/themes/argon/footer.htm
sed -i '/<a class="luci-link".*Powered by/d; /distversion/d; /ArgonTheme <%# vPKG_VERSION %>/s/ | *$//' package/new/extd/luci-theme-argon/luasrc/view/themes/argon/footer_login.htm

# Modify Hostname
log "Modifying hostname to HomeLab"
sed -i 's#OpenWrt#HomeLab#g' package/base-files/files/bin/config_generate

# Set CPU Mode
log "Setting CPU mode to PERFORMANCE"
sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND is not set/g' target/linux/x86/config-6.11
sed -i 's/CONFIG_CPU_FREQ_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_GOV_ONDEMAND is not set/g' target/linux/x86/config-6.11
sed -i 's/# CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE is not set/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' target/linux/x86/config-6.11
sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' target/linux/x86/64/config-6.11
sed -i 's/CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_GOV_PERFORMANCE=y/g' target/linux/x86/64/config-6.11

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
sed -i '/exit 0/d' $ZZZ && echo "exit 0" >> $ZZZ

# Move configuration files
log "Removing sysctl.d and creating tmp directory"
rm -rf files/etc/sysctl.d
REPO_TEMP_DIR=$(mktemp -d)
log "Downloading pre-configuration files"
curl -s -S -f -L -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" -o "$REPO_TEMP_DIR/repo.zip" 2>/dev/null
unzip -q "$REPO_TEMP_DIR/repo.zip" -d "$REPO_TEMP_DIR/"
log "Setting up pre-configuration files"
mv "$REPO_TEMP_DIR"/*/Lite/files/etc/* files/etc/
rm -rf "$REPO_TEMP_DIR"

log "Pre-downloading zashboard UI"
mkdir -p files/etc/nikki/run/ui/zashboard
ZASHBOARD_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip"
TEMP_DIR=$(mktemp -d)
wget -q --no-show-progress -O "$TEMP_DIR/dist.zip" "$ZASHBOARD_URL" 2>/dev/null
unzip -qq "$TEMP_DIR/dist.zip" -d "$TEMP_DIR" 2>/dev/null
find "$TEMP_DIR" -mindepth 2 -exec cp -r {} files/etc/nikki/run/ui/zashboard/ \; 2>/dev/null || cp -r "$TEMP_DIR"/* files/etc/nikki/run/ui/zashboard/
rm -rf "$TEMP_DIR"

# Pre-downloading MosDNS rules
log "Pre-downloading MosDNS rules"
mkdir -p files/etc/mosdns/rule
MOSDNS_APPLE_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/apple.txt"
MOSDNS_REJECT_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/reject.txt"
wget -qO- $MOSDNS_APPLE_URL > files/etc/mosdns/rule/apple.txt &
wget -qO- $MOSDNS_REJECT_URL > files/etc/mosdns/rule/reject.txt &
wait

log "Script completed successfully"
