#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

section() {
    echo ""
    echo "========== $1 =========="
}

section "First Boot Setup"

log "Generating uci-defaults settings"
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-settings <<-SETTINGS
#!/bin/sh

# Set Password
sed -i 's|root:::0:99999:7:::|root:$ROOT_PASSWORD_HASH:20211:0:99999:7:::|g' /etc/shadow

# Set VLAN Device
uci add network device
uci set network.@device[-1].type='8021q'
uci set network.@device[-1].ifname='eth1'
uci set network.@device[-1].vid='$VLAN_ID'
uci set network.@device[-1].name='eth1.$VLAN_ID'
uci set network.@device[-1].macaddr='$PPPOE_MAC'
uci set network.@device[-1].ipv6='0'
uci commit network

# Set PPPOE Dial-up
uci set network.wan.device='eth1.$VLAN_ID'
uci set network.wan.proto='pppoe'
uci set network.wan.username='$PPPOE_USERNAME'
uci set network.wan.password='$PPPOE_PASSWORD'
uci add network device
uci set network.@device[-1].name='pppoe-wan'
uci set network.@device[-1].macaddr='$PPPOE_WAN_MAC'
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
uci commit dhcp

# Disable Flow offloading HW
uci del firewall.@defaults[0].flow_offloading_hw
uci set firewall.@defaults[0].flow_offloading='1'
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
SETTINGS

if [ "$ENABLE_DUAL_WAN" = "true" ]; then
    log "Dual WAN enabled, appending WAN2 configuration"
    cat >> files/etc/uci-defaults/99-custom-settings <<-'DUALWAN'

# Dual WAN - VLAN Device for WAN2
uci add network device
uci set network.@device[-1].type='8021q'
uci set network.@device[-1].ifname='eth2'
DUALWAN

    cat >> files/etc/uci-defaults/99-custom-settings <<-DUALWAN
uci set network.@device[-1].vid='$VLAN_ID_2'
uci set network.@device[-1].name='eth2.$VLAN_ID_2'
uci set network.@device[-1].macaddr='$PPPOE_MAC_2'
uci set network.@device[-1].ipv6='0'
uci commit network

# Dual WAN - PPPOE for WAN2
uci set network.wan.metric='10'
uci set network.wan.dns_metric='10'
uci set network.wan.multipath='off'
uci commit network
uci set network.wan2=interface
uci set network.wan2.device='eth2.$VLAN_ID_2'
uci set network.wan2.proto='pppoe'
uci set network.wan2.username='$PPPOE_USERNAME_2'
uci set network.wan2.password='$PPPOE_PASSWORD_2'
uci set network.wan2.metric='20'
uci set network.wan2.dns_metric='20'
uci set network.wan2.multipath='off'
uci set network.wan2.ipv6='0'
uci set network.wan2.sourcefilter='0'
uci set network.wan2.delegate='0'
uci add network device
uci set network.@device[-1].name='pppoe-wan2'
uci set network.@device[-1].macaddr='$PPPOE_WAN_MAC_2'
uci set network.@device[-1].ipv6='0'
uci commit network
uci set dhcp.wan2=dhcp
uci set dhcp.wan2.interface='wan2'
uci set dhcp.wan2.ignore='1'
uci commit dhcp

# Dual WAN - Add WAN2 to firewall wan zone
uci add_list firewall.@zone[1].network='wan2'
uci commit firewall
DUALWAN
fi

echo "exit 0" >> files/etc/uci-defaults/99-custom-settings

section "Scheduled Tasks"
# Add customized task to crontabs
mkdir -p files/etc/crontabs
log "Adding cache drop task to crontabs"
echo "4 4 */3 * * sync && echo 3 > /proc/sys/vm/drop_caches" >> files/etc/crontabs/root

if [ -x files/usr/share/task/update_mosdns_rules.sh ]; then
    log "Adding MosDNS rules update task to crontabs"
    echo "33 3 * * 6 /usr/share/task/update_mosdns_rules.sh > /dev/null 2>&1" >> files/etc/crontabs/root
else
    log "Warning: MosDNS rules update script not found, skipping crontab"
fi

log "Settings.sh completed"
