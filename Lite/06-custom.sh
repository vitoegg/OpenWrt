#!/bin/bash -e

### Add new packages or patches below
### For example, download alist from a third-party repository to package/new/alist
### Then, add CONFIG_PACKAGE_luci-app-alist=y to the end of openwrt/23-config-common-custom

# Logging function
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg"
}

# REMOVE_PKG: Remove matching package directories from package/new/
# Usage: REMOVE_PKG <name> [name2] [name3] ...
REMOVE_PKG() {
    for name in "$@"; do
        log "Searching: $name"
        local found
        found=$(find package/new/ -maxdepth 3 -type d -iname "*$name*" 2>/dev/null)
        if [ -n "$found" ]; then
            while read -r dir; do
                rm -rf "$dir"
                log "Removed: $dir"
            done <<< "$found"
        else
            log "Not found: $name"
        fi
    done
}

# CLONE_PKG: Clone a GitHub repo into a target path under package/new/extd/
# Usage: CLONE_PKG <repo> <branch> [dest_name]
#   dest_name: optional directory name (defaults to repo basename)
CLONE_PKG() {
    local repo=$1
    local branch=$2
    local dest_name=${3:-${repo#*/}}
    local dest="package/new/extd/$dest_name"
    log "Cloning $repo ($branch) -> $dest"
    git clone --depth=1 --single-branch -b "$branch" "https://github.com/${repo}.git" "$dest"
}

# ===== Package Installation =====

# Nikki - replace built-in with customized version
REMOVE_PKG "nikki"
CLONE_PKG "vitoegg/OpenNikki" "master"

# Argon - replace built-in with customized theme
REMOVE_PKG "luci-theme-argon"
CLONE_PKG "vitoegg/Argon" "main" "luci-theme-argon"

# SmartDNS - remove due to unsatisfied build dependencies in upstream Makefile
REMOVE_PKG "smartdns"

# Modify Hostname
log "Modifying hostname to HomeLab"
sed -i 's#OpenWrt#HomeLab#g' package/base-files/files/bin/config_generate

# Set CPU Mode
log "Setting CPU mode to PERFORMANCE"
KERNEL_CONFIG=$(find target/linux/x86 -maxdepth 1 -name 'config-*' -type f | head -1)
KERNEL_CONFIG_64=$(find target/linux/x86/64 -maxdepth 1 -name 'config-*' -type f 2>/dev/null | head -1)

if [ -n "$KERNEL_CONFIG" ]; then
    log "Found kernel config: $KERNEL_CONFIG"
    sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND is not set/g' "$KERNEL_CONFIG"
    sed -i 's/CONFIG_CPU_FREQ_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_GOV_ONDEMAND is not set/g' "$KERNEL_CONFIG"
    sed -i 's/# CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE is not set/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' "$KERNEL_CONFIG"
fi

if [ -n "$KERNEL_CONFIG_64" ]; then
    log "Found kernel config (64-bit): $KERNEL_CONFIG_64"
    sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' "$KERNEL_CONFIG_64"
    sed -i 's/CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_GOV_PERFORMANCE=y/g' "$KERNEL_CONFIG_64"
fi

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

# Set VLAN Device
uci add network device
uci set network.@device[-1].type='8021q'
uci set network.@device[-1].ifname='eth1'
uci set network.@device[-1].vid='$VLAN_ID'
uci set network.@device[-1].name='eth1.$VLAN_ID'
uci set network.@device[-1].macaddr='$VLAN_MAC'
uci set network.@device[-1].ipv6='0'
uci commit network

# Set PPPOE Dial-up
uci set network.wan.device='eth1.$VLAN_ID'
uci set network.wan.proto='pppoe'
uci set network.wan.username='$PPPOE_USERNAME'
uci set network.wan.password='$PPPOE_PASSWORD'
uci add network device
uci set network.@device[-1].name='pppoe-wan'
uci set network.@device[-1].macaddr='$PPPOE_MAC'
uci set network.@device[-1].ipv6='0'
uci commit network

# Disable IPV6 Network
uci delete network.wan6
uci delete network.globals.ula_prefix
uci set network.@device[-1].ipv6='0'
uci set network.wan.sourcefilter='0'
uci set network.wan.ipv6='0'
uci set network.wan.delegate='0'
uci set network.lan.delegate='0'
uci set network.lan.ip6assign=''
uci commit network
uci set dhcp.lan.ra=''
uci set dhcp.lan.dhcpv6=''
uci set dhcp.lan.ra_management=''
uci set dhcp.@dnsmasq[0].filter_aaaa='1'
uci commit dhcp

# Set Static DHCP
uci add dhcp host
uci set dhcp.@host[-1].name='Router'
uci set dhcp.@host[-1].mac='$ROUTER_MAC'
uci set dhcp.@host[-1].ip='192.168.10.3'
uci set dhcp.@host[-1].dns="1"
uci set dhcp.@host[-1].leasetime='infinite'
uci add dhcp host
uci set dhcp.@host[-1].name='LMini'
uci set dhcp.@host[-1].mac='$LMINI_MAC'
uci set dhcp.@host[-1].ip='192.168.10.5'
uci set dhcp.@host[-1].dns="1"
uci set dhcp.@host[-1].leasetime='infinite'
uci commit dhcp

# Enable Shortcut-FE
uci del firewall.@defaults[0].flow_offloading
uci set firewall.@defaults[0].shortcut_fe='1'
uci set firewall.@defaults[0].shortcut_fe_module='shortcut-fe-cm'
uci commit firewall

# Enable Transmit Firewall
uci add firewall redirect
uci set firewall.@redirect[-1].name='Transmit'
uci set firewall.@redirect[-1].dest='lan'
uci set firewall.@redirect[-1].target='DNAT'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].src_dport='$REDIRECT_SRC_DPORT'
uci set firewall.@redirect[-1].dest_ip='192.168.10.2'
uci set firewall.@redirect[-1].dest_port='$REDIRECT_DEST_PORT'
uci commit firewall

EOF
sed -i '/exit 0/d' $ZZZ && echo "exit 0" >> $ZZZ

# Move configuration files
log "Downloading pre-configuration files"
REPO_TEMP_DIR=$(mktemp -d)
curl -s -S -f -L -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" -o "$REPO_TEMP_DIR/repo.zip" 2>/dev/null
unzip -q "$REPO_TEMP_DIR/repo.zip" -d "$REPO_TEMP_DIR/"
log "Setting up pre-configuration files"
# Remove existing files/etc directory and recreate it
rm -rf files/etc && mkdir -p files/etc
mv "$REPO_TEMP_DIR"/*/Lite/files/etc/* files/etc/
rm -rf "$REPO_TEMP_DIR"

# Pre-downloading MosDNS rules
log "Pre-downloading MosDNS rules"
mkdir -p files/etc/mosdns/rule
MOSDNS_APPLE_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/apple.txt"
MOSDNS_REJECT_URL="https://raw.githubusercontent.com/vitoegg/Provider/master/RuleSet/Extra/MosDNS/reject.txt"
wget -qO- $MOSDNS_APPLE_URL > files/etc/mosdns/rule/apple.txt &
wget -qO- $MOSDNS_REJECT_URL > files/etc/mosdns/rule/reject.txt &
wait

# Pre-downloading Nikki necessary files
# >Remove existing nikki ui directory
if [ -d "files/etc/nikki/run/ui" ]; then
    log "Removing existing nikki ui directory"
    rm -rf files/etc/nikki/run/ui
fi
# >Download Nikki zashboard UI
log "Downloading Nikki zashboard UI"
mkdir -p files/etc/nikki/run/ui/zashboard
ZASHBOARD_URL="https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip"
TEMP_DIR=$(mktemp -d)
wget -q --no-show-progress -O "$TEMP_DIR/dist.zip" "$ZASHBOARD_URL" 2>/dev/null
unzip -qq "$TEMP_DIR/dist.zip" -d "$TEMP_DIR" 2>/dev/null
find "$TEMP_DIR" -mindepth 2 -exec cp -r {} files/etc/nikki/run/ui/zashboard/ \; 2>/dev/null || cp -r "$TEMP_DIR"/* files/etc/nikki/run/ui/zashboard/
rm -rf "$TEMP_DIR"

log "Script completed successfully"