#!/bin/bash -e

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_profile "${1:?Usage: ApplyPatches.sh <Router|Cloud>}"

PATCH_ROOT="$REPO_ROOT/Build/Patches"

apply_source_patch() {
    local patch_file="$1"
    local label="$2"

    require_file "$patch_file" "$label patch file"

    log "Applying $label"
    if git apply --check "$patch_file" >/dev/null 2>&1; then
        git apply "$patch_file"
        log "$label patch applied successfully"
    elif git apply --reverse --check "$patch_file" >/dev/null 2>&1; then
        log "$label patch already applied"
    else
        log "ERROR: $label patch failed"
        git apply --check "$patch_file"
        exit 1
    fi
}

assert_file_contains() {
    local file="$1"
    local expected="$2"
    local label="$3"

    require_file "$file" "$label verification target"
    if ! grep -qF "$expected" "$file"; then
        log "ERROR: $label verification failed"
        exit 1
    fi
}

assert_file_not_contains() {
    local file="$1"
    local unexpected="$2"
    local label="$3"

    require_file "$file" "$label verification target"
    if grep -qF "$unexpected" "$file"; then
        log "ERROR: $label verification failed"
        exit 1
    fi
}

patch_hostname_ip() {
    local config_generate="package/base-files/files/bin/config_generate"
    local flash_js

    section "Hostname and IP"

    require_file "$config_generate" "config_generate"

    log "Setting default IP to $DEFAULT_IP"
    sed -i "s/192\\.168\\.[0-9]*\\.[0-9]*/$DEFAULT_IP/g" "$config_generate"

    log "Modifying immortalwrt.lan redirect IP"
    flash_js=$(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" 2>/dev/null)
    if [ -n "$flash_js" ] && [ -f "$flash_js" ]; then
        sed -i "s/192\\.168\\.[0-9]*\\.[0-9]*/$DEFAULT_IP/g" "$flash_js"
        log "LuCI flash redirect IP patched"
    else
        log "Warning: LuCI flash.js not found, skipping redirect IP patch"
    fi

    log "Modifying hostname to $DEVICE_NAME"
    sed -i "s/hostname='.*'/hostname='$DEVICE_NAME'/g" "$config_generate"
}

patch_build_version() {
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

patch_x86_cpu_performance() {
    section "X86 CPU Performance Patch"

    apply_source_patch "$PATCH_ROOT/X86/010-kernel-cpufreq-performance.patch" "x86 CPU frequency performance"

    assert_file_contains "config/Config-kernel.in" "default KERNEL_CPU_FREQ_DEFAULT_GOV_PERFORMANCE" "x86 CPU frequency performance"
}

patch_imagebuilder() {
    local imagebuilder_makefile="target/imagebuilder/Makefile"

    section "ImageBuilder Patches"

    apply_source_patch "$PATCH_ROOT/ImageBuilder/010-standalone-apk-repositories.patch" "standalone APK repositories"

    assert_file_contains "$imagebuilder_makefile" 'touch $(PKG_BUILD_DIR)/repositories' "standalone APK repositories"
}

patch_luci_common() {
    local led_menu_file="feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json"
    local dhcp_file="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/40_dhcp.js"

    section "LuCI Common Patches"

    apply_source_patch "$PATCH_ROOT/LuCI/010-remove-led-menu.patch" "LuCI LED menu"
    apply_source_patch "$PATCH_ROOT/LuCI/020-dhcp-lease-display.patch" "LuCI DHCP lease display"
    assert_file_not_contains "$led_menu_file" '"admin/system/leds"' "LuCI LED menu"
    assert_file_contains "$dhcp_file" "return result.length ? E(result) : null;" "LuCI DHCP lease display"
}

patch_router_luci() {
    local interfaces_file="feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/interfaces.js"

    section "Router LuCI Patches"

    apply_source_patch "$PATCH_ROOT/LuCI/060-hide-alias-carrier-status.patch" "LuCI alias carrier status"
    assert_file_contains "$interfaces_file" "_('Carrier'), cond00 ? (carrier ? _('Present') : _('Absent')) : null," "LuCI alias carrier status"
}

patch_cloud_docker_runtime() {
    local dockerd_makefile="feeds/packages/utils/dockerd/Makefile"
    local dockerd_init="feeds/packages/utils/dockerd/files/dockerd.init"

    section "Docker Runtime Patches"

    apply_source_patch "$PATCH_ROOT/Docker/010-dockerd-remove-iptables-deps.patch" "dockerd dependency cleanup"
    apply_source_patch "$PATCH_ROOT/Docker/020-dockerd-host-mode.patch" "dockerd host mode"

    if grep -Eq '^[[:space:]]*\+(iptables|iptables-mod-extra|IPV6:ip6tables|IPV6:kmod-ipt-nat6|kmod-ipt-nat|kmod-ipt-physdev)([[:space:]]|\\|$)' "$dockerd_makefile"; then
        log "ERROR: dockerd dependency cleanup verification failed"
        exit 1
    fi

    if sed -n '/^boot() {/,/^}/p' "$dockerd_init" | grep -q 'uciadd'; then
        log "ERROR: dockerd host mode boot verification failed"
        exit 1
    fi

    assert_file_contains "$dockerd_init" 'config_get bridge globals bridge ""' "dockerd bridge option"
    assert_file_contains "$dockerd_init" 'json_add_string "bridge" "${bridge}"' "dockerd bridge option"
}

patch_cloud_luci() {
    local ports_file="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/29_ports.js"
    local status_po="feeds/luci/modules/luci-base/po/zh_Hans/base.po"
    local mio_menu_file="package/custom/luci-app-mio/luci-app-mio/root/usr/share/luci/menu.d/luci-app-mio.json"

    section "Cloud LuCI Patches"

    apply_source_patch "$PATCH_ROOT/LuCI/030-port-status-table.patch" "LuCI port status table"
    apply_source_patch "$PATCH_ROOT/LuCI/040-port-status-zh-hans.patch" "LuCI port status zh_Hans"
    apply_source_patch "$PATCH_ROOT/LuCI/050-mio-menu.patch" "Mio LuCI menu"
    assert_file_contains "$ports_file" "No port information available" "LuCI port status table"
    assert_file_contains "$status_po" 'msgid "Speed"' "LuCI port status zh_Hans"
    assert_file_contains "$status_po" 'msgstr "速率"' "LuCI port status zh_Hans"
    assert_file_contains "$mio_menu_file" '"admin/vpn/mio"' "Mio LuCI menu"
    assert_file_not_contains "$mio_menu_file" '"admin/services/mio"' "Mio LuCI menu"
}

patch_bbrv3() {
    local patch_dir="$REPO_ROOT/Build/Patches/BBRv3"
    local target_kernel_patchver="6.12"
    local target_patch_dir="target/linux/generic/backport-$target_kernel_patchver"
    local target_makefile="target/linux/x86/Makefile"
    local expected_patch_count=20
    local kernel_patchver
    local patch_count

    section "BBRv3 Kernel Patch"

    require_file "include/kernel.mk" "OpenWrt kernel include"
    require_file "$target_makefile" "x86 target Makefile"
    require_dir "$patch_dir" "BBRv3 patch directory"
    require_dir "target/linux/generic" "OpenWrt generic target directory"

    kernel_patchver=$(sed -n 's/^KERNEL_PATCHVER:=//p' "$target_makefile" | head -1 | tr -d '[:space:]')

    if [ "$kernel_patchver" != "$target_kernel_patchver" ]; then
        log "ERROR: BBRv3 patches support kernel patch version $target_kernel_patchver, current target is ${kernel_patchver:-unknown}"
        exit 1
    fi

    patch_count=$(find "$patch_dir" -maxdepth 1 -type f -name '010-bbr3-*.patch' | wc -l | tr -d '[:space:]')

    if [ "$patch_count" -ne "$expected_patch_count" ]; then
        log "ERROR: Expected $expected_patch_count BBRv3 patches, found $patch_count"
        exit 1
    fi

    log "Installing BBRv3 patches for kernel patch version $target_kernel_patchver"
    mkdir -p "$target_patch_dir"
    rm -f "$target_patch_dir"/010-bbr3-*.patch
    cp "$patch_dir"/010-bbr3-*.patch "$target_patch_dir"/

    patch_count=$(find "$target_patch_dir" -maxdepth 1 -type f -name '010-bbr3-*.patch' | wc -l | tr -d '[:space:]')

    if [ "$patch_count" -ne "$expected_patch_count" ]; then
        log "ERROR: BBRv3 patch installation failed, copied $patch_count files"
        exit 1
    fi

    log "BBRv3 patches installed: $target_patch_dir"
}

patch_hostname_ip
patch_build_version
patch_imagebuilder
patch_x86_cpu_performance

if [ "$BUILD_PROFILE" = "Cloud" ]; then
    patch_cloud_docker_runtime
fi

patch_luci_common

if [ "$BUILD_PROFILE" = "Router" ]; then
    patch_router_luci
fi

if [ "$BUILD_PROFILE" = "Cloud" ]; then
    patch_cloud_luci
fi

patch_bbrv3

log "ApplyPatches.sh completed"
