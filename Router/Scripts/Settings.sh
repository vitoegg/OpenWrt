#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

remove_json_key() {
    local file=$1
    local key=$2
    local label=${3:-$key}

    if [ ! -f "$file" ]; then
        log "Warning: $label skipped, file not found: $file"
        return 0
    fi

    local result
    result=$(python3 - "$file" "$key" "$label" <<'PY'
from pathlib import Path
import json
import sys

target = Path(sys.argv[1])
key = sys.argv[2]
label = sys.argv[3]

try:
    data = json.loads(target.read_text())
except json.JSONDecodeError as exc:
    raise SystemExit(f"{label} failed: invalid JSON in {target}: {exc}")

removed = data.pop(key, None)

if removed is None:
    print("MISSING")
else:
    target.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print("REMOVED")
PY
)

    if [ $? -ne 0 ]; then
        return 1
    fi

    if [ "$result" = "REMOVED" ]; then
        log "$label applied successfully"
    else
        log "Warning: $label skipped, key not found: $key"
    fi
}

replace_text_once() {
    local file=$1
    local label=$2
    local old_block=$3
    local new_block=$4
    shift 4

    if [ ! -f "$file" ]; then
        log "Error: $label target file not found: $file"
        return 1
    fi

    PATCH_OLD="$old_block" PATCH_NEW="$new_block" python3 - "$file" "$label" "$@" <<'PY'
from pathlib import Path
import os
import sys

target = Path(sys.argv[1])
label = sys.argv[2]
markers = sys.argv[3:]
old = os.environ["PATCH_OLD"]
new = os.environ["PATCH_NEW"]
text = target.read_text()
matches = text.count(old)

if matches != 1:
    raise SystemExit(f"{label} failed: expected 1 match in {target}, found {matches}")

patched = text.replace(old, new, 1)

for marker in markers:
    if marker not in patched:
        raise SystemExit(f"{label} failed: missing marker '{marker}' after patch")

target.write_text(patched)
PY

    if [ $? -ne 0 ]; then
        return 1
    fi

    log "$label applied successfully"
}

# ===== Modify Default IP =====

log "Setting default IP to 192.168.10.1"
sed -i 's/192\.168\.[0-9]*\.[0-9]*/192.168.10.1/g' package/base-files/files/bin/config_generate

# ===== Modify LuCI Flash Redirect IP =====

log "Modifying immortalwrt.lan redirect IP"
FLASH_JS=$(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" 2>/dev/null)
if [ -n "$FLASH_JS" ] && [ -f "$FLASH_JS" ]; then
    sed -i 's/192\.168\.[0-9]*\.[0-9]*/192.168.10.1/g' "$FLASH_JS"
fi

# ===== Modify Hostname =====

log "Modifying hostname to HomeLab"
sed -i "s/hostname='.*'/hostname='HomeLab'/g" package/base-files/files/bin/config_generate

# ===== Customize Firmware Version =====

BUILD_DATE=$(TZ=UTC-8 date +'%y.%m.%d')

# ===== Remove APK Cheatsheet =====

APK_CHEATSHEET="package/base-files/files/etc/profile.d/apk-cheatsheet.sh"
if [ -f "$APK_CHEATSHEET" ]; then
    log "Removing APK cheatsheet"
    echo "# Intentionally left empty" > "$APK_CHEATSHEET"
fi

# ===== Customize Banner =====

log "Customizing banner"
rm -f files/etc/banner
BRANCH_VER=$(echo "$WRT_BRANCH" | sed 's/openwrt-//')
sed -i "s| %D %V, %C Dave's Guitar| ImmortalWrt $BRANCH_VER · Build $BUILD_DATE via GitHub|" package/base-files/files/etc/banner

# ===== Customize Firmware Version =====

log "Setting firmware version to: ImmortalWrt @ Build ${BUILD_DATE}"
sed -i "s/boardinfo.release.description/'ImmortalWrt @ Build ${BUILD_DATE}'/" \
  feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

# ===== Set CPU Performance Mode =====

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

# ===== Delete LED Menu =====

log "Removing LED menu from LuCI"
LED_MENU_FILE="feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json"
remove_json_key "$LED_MENU_FILE" "admin/system/leds" "LED menu removal"

# ===== Hide Empty DHCP Leases =====

log "Patching DHCP lease display to auto-hide when empty"
DHCP_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/40_dhcp.js"

# Detect DHCPv4 heading variant (25.12+) vs legacy DHCP heading
if grep -q "Active DHCPv4 Leases" "$DHCP_FILE" 2>/dev/null; then
    DHCP_V4_TITLE="Active DHCPv4 Leases"
else
    DHCP_V4_TITLE="Active DHCP Leases"
fi
log "Detected DHCPv4 heading: $DHCP_V4_TITLE"

DHCP_OLD_BLOCK=$'\t\treturn E([\n\t\t\tE(\'h3\', _(\''"$DHCP_V4_TITLE"$'\')),\n\t\t\ttable,\n\t\t\tE(\'h3\', _(\'Active DHCPv6 Leases\')),\n\t\t\ttable6\n\t\t]);\n'
DHCP_NEW_BLOCK=$'\t\tconst result = [];\n\t\tif (leases.length > 0) {\n\t\t\tresult.push(E(\'h3\', _(\''"$DHCP_V4_TITLE"$'\')));\n\t\t\tresult.push(table);\n\t\t}\n\t\tif (leases6.length > 0) {\n\t\t\tresult.push(E(\'h3\', _(\'Active DHCPv6 Leases\')));\n\t\t\tresult.push(table6);\n\t\t}\n\t\treturn E(result);\n'
replace_text_once \
    "$DHCP_FILE" \
    "DHCP lease display patch" \
    "$DHCP_OLD_BLOCK" \
    "$DHCP_NEW_BLOCK" \
    "if (leases.length > 0)" \
    "if (leases6.length > 0)" \
    "return E(result);"

# ===== Generate uci-defaults Script =====

log "Generating uci-defaults settings"
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-custom-settings <<-SETTINGS
#!/bin/sh

# Set Password
sed -i 's|root:::0:99999:7:::|root:$ROOT_PASSWORD_HASH:20211:0:99999:7:::|g' /etc/shadow

# Set Timezone to UTC+8
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci commit system

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
uci add dhcp host
uci set dhcp.@host[-1].name='LMini'
uci set dhcp.@host[-1].mac='$LMINI_MAC'
uci set dhcp.@host[-1].ip='192.168.10.5'
uci set dhcp.@host[-1].dns="1"
uci set dhcp.@host[-1].leasetime='infinite'
uci commit dhcp

# Enable Software Flow Offloading
uci set firewall.@defaults[0].flow_offloading='1'
uci del firewall.@defaults[0].flow_offloading_hw
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

# ===== Append Dual WAN Configuration (if enabled) =====

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
uci commit network
uci set network.wan2=interface
uci set network.wan2.device='eth2.$VLAN_ID_2'
uci set network.wan2.proto='pppoe'
uci set network.wan2.username='$PPPOE_USERNAME_2'
uci set network.wan2.password='$PPPOE_PASSWORD_2'
uci set network.wan2.metric='20'
uci set network.wan2.dns_metric='20'
uci set network.wan2.ipv6='0'
uci set network.wan2.sourcefilter='0'
uci set network.wan2.delegate='0'
uci add network device
uci set network.@device[-1].name='pppoe-wan2'
uci set network.@device[-1].macaddr='$PPPOE_WAN_MAC_2'
uci set network.@device[-1].ipv6='0'
uci commit network

# Dual WAN - Add WAN2 to firewall wan zone
uci add_list firewall.@zone[1].network='wan2'
uci commit firewall
DUALWAN
fi

# ===== Append exit 0 =====

echo "exit 0" >> files/etc/uci-defaults/99-custom-settings

log "Settings.sh completed"
