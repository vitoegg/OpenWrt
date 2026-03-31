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
# Usage: CLONE_PKG <repo> <branch> [dest_name]
CLONE_PKG() {
    local repo=$1
    local branch=$2
    local dest_name=${3:-${repo#*/}}
    local dest="$PKG_CLONE_BASE/$dest_name"
    local start=$SECONDS
    log "Cloning $repo ($branch) -> $dest"
    if ! git clone --depth=1 --single-branch -b "$branch" \
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

# Argon - replace built-in with customized theme
REMOVE_PKG "luci-theme-argon"
CLONE_PKG "vitoegg/Argon" "main" "luci-theme-argon"

# Mio - add personalized ssserver
CLONE_PKG "vitoegg/Mio" "master" "Mio"

# Apps not needed in the Cloud version
REMOVE_PKG \
    "smartdns" \
    "luci-app-dae"

# ===== System Settings =====

section "System Settings"

# Modify Hostname
log "Modifying hostname to HomeCloud"
sed -i 's#OpenWrt#HomeCloud#g' package/base-files/files/bin/config_generate

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

# Setting up etc config
log "Setting up etc config"
ZZZ="package/new/default-settings/default/zzz-default-settings"
cat >> $ZZZ <<-EOF
# Set customizedpassword
sed -i 's|root:::0:99999:7:::|root:$ROOT_PASSWORD_HASH:20211:0:99999:7:::|g' /etc/shadow
# Enable auto mount
uci set fstab.@global[0].anon_mount='1'
uci commit fstab
EOF
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
mv "$REPO_TEMP_DIR"/*/Cloud/files/etc/* files/etc/
rm -rf "$REPO_TEMP_DIR"

# Add docker restart task to crontabs
log "Adding docker restart task to crontabs"
mkdir -p files/etc/crontabs
echo "15 5 * * * docker restart tunnel" >> files/etc/crontabs/root

# Download ddns script
log "Downloading ddns script"
mkdir -p files/usr/share/task
wget -qO- $DDNS_SH_URL > files/usr/share/task/ddns.sh
chmod +x files/usr/share/task/ddns.sh
log "Adding ddns script to crontabs"
echo "*/30 * * * * /usr/share/task/ddns.sh > /dev/null 2>&1" >> files/etc/crontabs/root

log "Script completed successfully"
