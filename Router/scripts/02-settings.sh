#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Modify Default IP
log "Setting default IP to 192.168.10.1"
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# Modify Hostname
log "Modifying hostname to HomeLab"
sed -i 's/ImmortalWrt/HomeLab/g' package/base-files/files/bin/config_generate

# Set CPU Performance Mode (dynamic kernel version detection)
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
LED_MENU="feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json"
if [ -f "$LED_MENU" ]; then
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
' "$LED_MENU" > /tmp/temp.json && mv /tmp/temp.json "$LED_MENU"
fi

# Generate uci-defaults script
log "Generating uci-defaults settings"
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-settings <<-SETTINGS
#!/bin/sh

# Set Password
sed -i 's|root:::0:99999:7:::|root:$ROOT_PASSWORD_HASH:20211:0:99999:7:::|g' /etc/shadow

# Set PPPOE Dial-up
uci set network.wan.proto='pppoe'
uci set network.wan.username='$PPPOE_USERNAME'
uci set network.wan.password='$PPPOE_PASSWORD'
uci commit network

# Set PPPOE Device
uci add network device
uci set network.@device[-1].macaddr='$PPPOE_MAC'
uci set network.@device[-1].name='pppoe-wan'
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

exit 0
SETTINGS

log "02-settings.sh completed"
