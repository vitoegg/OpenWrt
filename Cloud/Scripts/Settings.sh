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

# Set Side Router Network
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.10.2'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='192.168.10.1'
uci -q delete network.lan.dns
uci add_list network.lan.dns='192.168.10.1'
uci set network.lan.ipv6='0'
uci set network.lan.delegate='0'
uci -q delete network.lan.ip6assign
uci -q delete network.lan.ip6hint
uci -q delete network.lan.ip6ifaceid
uci -q delete network.wan
uci -q delete network.wan6
uci -q delete network.globals.ula_prefix
uci commit network

# Disable DHCP and IPv6 on LAN
uci set dhcp.lan.ignore='1'
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ndp='disabled'
uci set dhcp.@dnsmasq[0].filter_aaaa='1'
uci -q delete dhcp.wan
uci commit dhcp

# Remove WAN Firewall
while true; do
    WAN_RULE=\$(uci -q show firewall | sed -n "/\\.dest='wan'$/s/\\.dest='wan'$//p; /\\.src='wan'$/s/\\.src='wan'$//p" | head -n 1)
    [ -n "\$WAN_RULE" ] || break
    uci -q delete "\$WAN_RULE" || break
done

while true; do
    WAN_ZONE=\$(uci -q show firewall | sed -n "/\\.name='wan'$/s/\\.name='wan'$//p" | head -n 1)
    [ -n "\$WAN_ZONE" ] || break
    uci -q delete "\$WAN_ZONE" || break
done

# Disable Flow offloading HW
uci del firewall.@defaults[0].flow_offloading_hw
uci set firewall.@defaults[0].flow_offloading='1'
uci commit firewall

# Enable Auto Mount
uci set fstab.@global[0].anon_mount='1'
uci commit fstab

# Set Docker daemon for host-network containers
uci set dockerd.globals='globals'
uci set dockerd.globals.data_root='/mnt/sda1/docker'
uci set dockerd.globals.log_level='error'
uci set dockerd.globals.iptables='0'
uci set dockerd.globals.ip6tables='0'
uci set dockerd.globals.bridge='none'
uci commit dockerd
SETTINGS

echo "exit 0" >> files/etc/uci-defaults/99-custom-settings

section "Scheduled Tasks"

mkdir -p files/etc/crontabs
log "Adding docker restart task to crontabs"
echo "15 5 * * * docker restart tunnel" >> files/etc/crontabs/root

log "Adding cache drop task to crontabs"
echo "0 */3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >> files/etc/crontabs/root

if [ -x files/usr/share/task/ddns.sh ]; then
    log "Adding DDNS task to crontabs"
    echo "*/30 * * * * /usr/share/task/ddns.sh > /dev/null 2>&1" >> files/etc/crontabs/root
else
    log "Warning: DDNS script not found, skipping crontab"
fi

log "Settings.sh completed"
