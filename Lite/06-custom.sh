#!/bin/bash -e

# ===== Variant Configuration =====
PKG_SEARCH_PATHS="package/new/"
PKG_CLONE_BASE="package/new/extd"

# ===== Common Helper Functions =====

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

section() {
    echo ""
    echo "========== $1 =========="
}

# REMOVE_PKG: Remove matching package directories
# Usage: REMOVE_PKG <name> [name2] [name3] ...
REMOVE_PKG() {
    for name in "$@"; do
        log "Removing: $name"
        local found
        found=$(find $PKG_SEARCH_PATHS -maxdepth 3 -type d -iname "*$name*" 2>/dev/null)
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

# CLONE_PKG: Clone a GitHub repo into $PKG_CLONE_BASE/
# Usage: CLONE_PKG <repo> [--branch <branch>] [--name <dest_name>]
#   Omit --branch to use the repo's default branch
CLONE_PKG() {
    local repo=$1; shift
    local branch="" dest_name=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --branch) branch=$2; shift 2 ;;
            --name)   dest_name=$2; shift 2 ;;
            *)        shift ;;
        esac
    done
    dest_name=${dest_name:-${repo#*/}}
    local dest="$PKG_CLONE_BASE/$dest_name"
    local start=$SECONDS
    local branch_args=""
    local branch_label="default"
    if [ -n "$branch" ]; then
        branch_args="-b $branch"
        branch_label="$branch"
    fi
    log "Cloning $repo ($branch_label) -> $dest"
    if ! git clone --depth=1 --single-branch $branch_args \
        "https://github.com/${repo}.git" "$dest"; then
        log "ERROR: Failed to clone $repo"
        return 1
    fi
    log "Cloned $repo ($((SECONDS - start))s)"
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

# ===== Package Installation =====

section "Package Installation"

# Nikki - replace built-in with customized version
REMOVE_PKG "nikki"
CLONE_PKG "vitoegg/OpenNikki"

# Argon - replace built-in with customized theme
REMOVE_PKG "luci-theme-argon"
CLONE_PKG "vitoegg/Argon" --name "luci-theme-argon"

# Apps not needed in the Lite version
REMOVE_PKG \
    "smartdns" \
    "luci-app-dae"

# ===== System Settings =====

section "System Settings"

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
LED_MENU_FILE="feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json"
remove_json_key "$LED_MENU_FILE" "admin/system/leds" "LED menu removal"

# Hide empty DHCP/DHCPv6 Leases section on status overview page
log "Patching DHCP lease display to auto-hide when empty"
DHCP_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/40_dhcp.js"
DHCP_OLD_BLOCK=$'\t\treturn E([\n\t\t\tE(\'h3\', _(\'Active DHCP Leases\')),\n\t\t\ttable,\n\t\t\tE(\'h3\', _(\'Active DHCPv6 Leases\')),\n\t\t\ttable6\n\t\t]);\n'
DHCP_NEW_BLOCK=$'\t\tconst result = [];\n\t\tif (leases.length > 0) {\n\t\t\tresult.push(E(\'h3\', _(\'Active DHCP Leases\')));\n\t\t\tresult.push(table);\n\t\t}\n\t\tif (leases6.length > 0) {\n\t\t\tresult.push(E(\'h3\', _(\'Active DHCPv6 Leases\')));\n\t\t\tresult.push(table6);\n\t\t}\n\t\treturn E(result);\n'
replace_text_once \
    "$DHCP_FILE" \
    "DHCP lease display patch" \
    "$DHCP_OLD_BLOCK" \
    "$DHCP_NEW_BLOCK" \
    "if (leases.length > 0)" \
    "if (leases6.length > 0)" \
    "return E(result);"

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

# Dual WAN Configuration
if [ "$ENABLE_DUAL_WAN" = "true" ]; then
    log "Dual WAN enabled, appending WAN2 configuration"
    cat >> $ZZZ <<-DUALWAN

# Dual WAN - VLAN Device for WAN2
uci add network device
uci set network.@device[-1].type='8021q'
uci set network.@device[-1].ifname='eth2'
uci set network.@device[-1].vid='$VLAN_ID_2'
uci set network.@device[-1].name='eth2.$VLAN_ID_2'
uci set network.@device[-1].macaddr='$PPPOE_MAC_2'
uci set network.@device[-1].ipv6='0'
uci commit network

# Dual WAN - Set WAN metric (primary)
uci set network.wan.metric='10'
uci set network.wan.dns_metric='10'
uci commit network

# Dual WAN - PPPOE for WAN2 (backup)
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

sed -i '/exit 0/d' $ZZZ && echo "exit 0" >> $ZZZ

# ===== Configuration Files =====

section "Configuration Files"

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

# ===== Pre-downloads =====

section "Pre-downloads"

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
