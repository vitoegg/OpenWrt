#!/bin/bash -e

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

section() {
    echo ""
    echo "========== $1 =========="
}

require_file() {
    local file="$1"
    local label="$2"

    if [ ! -f "$file" ]; then
        log "ERROR: ${label} not found: $file"
        exit 1
    fi
}

patch_router_name_and_ip() {
    local config_generate="package/base-files/files/bin/config_generate"
    local flash_js

    section "Router Name and IP"

    require_file "$config_generate" "config_generate"

    log "Setting default IP to 192.168.10.1"
    sed -i 's/192\.168\.[0-9]*\.[0-9]*/192.168.10.1/g' "$config_generate"

    log "Modifying immortalwrt.lan redirect IP"
    flash_js=$(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" 2>/dev/null)
    if [ -n "$flash_js" ] && [ -f "$flash_js" ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/192.168.10.1/g' "$flash_js"
        log "LuCI flash redirect IP patched"
    else
        log "Warning: LuCI flash.js not found, skipping redirect IP patch"
    fi

    log "Modifying hostname to HomeLab"
    sed -i "s/hostname='.*'/hostname='HomeLab'/g" "$config_generate"
}

patch_build_version_and_banner() {
    local apk_cheatsheet="package/base-files/files/etc/profile.d/apk-cheatsheet.sh"
    local banner_file="package/base-files/files/etc/banner"
    local branch_ver
    local banner_text
    local firmware_version
    local os_release_file="package/base-files/files/usr/lib/os-release"
    local openwrt_release_file="package/base-files/files/etc/openwrt_release"

    section "Build Version and Banner"

    if [ -z "$BUILD_DATE" ]; then
        BUILD_DATE=$(TZ=Asia/Shanghai date +'%y.%m.%d')
        log "BUILD_DATE not set by workflow, using local: $BUILD_DATE"
    fi

    if [ -f "$apk_cheatsheet" ]; then
        log "Removing APK cheatsheet"
        echo "# Intentionally left empty" > "$apk_cheatsheet"
    fi

    log "Customizing banner"
    rm -f files/etc/banner

    require_file "$banner_file" "banner file"

    branch_ver=$(echo "$WRT_BRANCH" | sed 's/openwrt-//')
    banner_text=" ImmortalWrt $branch_ver · Build $BUILD_DATE via GitHub"
    sed -i "s|^ %D %V, %C.*$|$banner_text|" "$banner_file"

    if grep -qF "$banner_text" "$banner_file"; then
        log "Banner patch applied successfully"
    else
        log "ERROR: Banner patch failed: expected line not found"
        exit 1
    fi

    firmware_version="ImmortalWrt @ Build $BUILD_DATE"
    log "Setting firmware version: ${firmware_version}"

    require_file "$os_release_file" "os-release file"
    if grep -q 'OPENWRT_RELEASE="%D %V %C"' "$os_release_file"; then
        sed -i "s#OPENWRT_RELEASE=\"%D %V %C\"#OPENWRT_RELEASE=\"$firmware_version\"#" "$os_release_file"
        log "Firmware version os-release patch applied successfully"
    elif grep -q "OPENWRT_RELEASE=\"$firmware_version\"" "$os_release_file"; then
        log "Firmware version os-release patch already applied"
    else
        log "ERROR: Firmware version os-release patch failed: expected line not found"
        exit 1
    fi

    require_file "$openwrt_release_file" "openwrt_release file"
    if grep -q "DISTRIB_DESCRIPTION='%D %V %C'" "$openwrt_release_file"; then
        sed -i "s#DISTRIB_DESCRIPTION='%D %V %C'#DISTRIB_DESCRIPTION='$firmware_version'#" "$openwrt_release_file"
        log "Firmware version openwrt_release patch applied successfully"
    elif grep -q "DISTRIB_DESCRIPTION='$firmware_version'" "$openwrt_release_file"; then
        log "Firmware version openwrt_release patch already applied"
    else
        log "ERROR: Firmware version openwrt_release patch failed: expected line not found"
        exit 1
    fi
}

patch_cpu_performance() {
    local kernel_config
    local kernel_config_64

    section "CPU Performance"

    log "Setting CPU mode to PERFORMANCE"
    kernel_config=$(find target/linux/x86 -maxdepth 1 -name 'config-*' -type f | head -1)
    kernel_config_64=$(find target/linux/x86/64 -maxdepth 1 -name 'config-*' -type f 2>/dev/null | head -1)

    if [ -n "$kernel_config" ]; then
        log "Found kernel config: $kernel_config"
        sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND is not set/g' "$kernel_config"
        sed -i 's/CONFIG_CPU_FREQ_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_GOV_ONDEMAND is not set/g' "$kernel_config"
        sed -i 's/# CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE is not set/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' "$kernel_config"
    else
        log "Warning: x86 kernel config not found, skipping base CPU governor patch"
    fi

    if [ -n "$kernel_config_64" ]; then
        log "Found kernel config (64-bit): $kernel_config_64"
        sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' "$kernel_config_64"
        sed -i 's/CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_GOV_PERFORMANCE=y/g' "$kernel_config_64"
    else
        log "Warning: x86/64 kernel config not found, skipping 64-bit CPU governor patch"
    fi
}

patch_luci_led_menu() {
    local led_menu_file="feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json"
    local led_result

    log "Removing LED menu from LuCI"

    if [ ! -f "$led_menu_file" ]; then
        log "Warning: LED menu removal skipped, file not found: $led_menu_file"
        return
    fi

    led_result=$(python3 - "$led_menu_file" <<'PY'
from pathlib import Path
import json
import sys

target = Path(sys.argv[1])
data = json.loads(target.read_text())

if data.pop("admin/system/leds", None) is None:
    print("MISSING")
else:
    target.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print("REMOVED")
PY
)

    if [ "$led_result" = "REMOVED" ]; then
        log "LED menu removal applied successfully"
    else
        log "Warning: LED menu removal skipped, key not found: admin/system/leds"
    fi
}

patch_dhcp_lease_display() {
    local dhcp_file="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/40_dhcp.js"
    local dhcp_v4_title
    local dhcp_result

    log "Patching DHCP lease display to auto-hide when empty"

    require_file "$dhcp_file" "DHCP lease display patch target file"

    if grep -q "Active DHCPv4 Leases" "$dhcp_file" 2>/dev/null; then
        dhcp_v4_title="Active DHCPv4 Leases"
    else
        dhcp_v4_title="Active DHCP Leases"
    fi
    log "Detected DHCPv4 heading: $dhcp_v4_title"

    dhcp_result=$(DHCP_V4_TITLE="$dhcp_v4_title" python3 - "$dhcp_file" <<'PY'
from pathlib import Path
import os
import sys

target = Path(sys.argv[1])
title = os.environ["DHCP_V4_TITLE"]
text = target.read_text()
empty_old = "\t\tif (leases.length == 0 && leases6.length == 0)\n\t\t\treturn E('em', _('No active leases found'));\n"
empty_new = "\t\tif (leases.length == 0 && leases6.length == 0)\n\t\t\treturn null;\n"
return_old = f"\t\treturn E([\n\t\t\tE('h3', _('{title}')),\n\t\t\ttable,\n\t\t\tE('h3', _('Active DHCPv6 Leases')),\n\t\t\ttable6\n\t\t]);\n"
return_new = f"\t\tconst result = [];\n\t\tif (leases.length > 0) {{\n\t\t\tresult.push(E('h3', _('{title}')));\n\t\t\tresult.push(table);\n\t\t}}\n\t\tif (leases6.length > 0) {{\n\t\t\tresult.push(E('h3', _('Active DHCPv6 Leases')));\n\t\t\tresult.push(table6);\n\t\t}}\n\t\treturn result.length ? E(result) : null;\n"
return_patched_old = return_new.replace("return result.length ? E(result) : null;", "return E(result);")

changed = False

if empty_old in text:
    text = text.replace(empty_old, empty_new, 1)
    changed = True

if return_old in text:
    text = text.replace(return_old, return_new, 1)
    changed = True
elif return_patched_old in text:
    text = text.replace(return_patched_old, return_new, 1)
    changed = True

if changed:
    target.write_text(text)
    print("PATCHED")
elif "if (leases.length > 0)" in text and "if (leases6.length > 0)" in text and "return result.length ? E(result) : null;" in text:
    print("UNCHANGED")
else:
    raise SystemExit(f"DHCP lease display patch failed: expected block not found in {target}")
PY
)

    if [ "$dhcp_result" = "PATCHED" ]; then
        log "DHCP lease display patch applied successfully"
    else
        log "DHCP lease display patch already applied"
    fi
}

patch_luci_menu_and_status() {
    section "LuCI Menu and Status"

    patch_luci_led_menu
    patch_dhcp_lease_display
}

main() {
    patch_router_name_and_ip
    patch_build_version_and_banner
    patch_cpu_performance
    patch_luci_menu_and_status

    log "Patch.sh completed"
}

main "$@"
