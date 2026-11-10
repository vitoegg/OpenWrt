#!/bin/bash

# Patches the OpenWrt source tree and verifies every change

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"

load_profile "${1:?Usage: patches.sh <Router|Cloud>}"

PATCH_ROOT="$REPO_ROOT/patches"

apply_source_patch() {
    local patch_file="$1"
    local label="$2"

    require_file "$patch_file" "Patch file"

    if git apply --check "$patch_file" >/dev/null 2>&1; then
        git apply "$patch_file"
        log_ok "$label"
    elif git apply --reverse --check "$patch_file" >/dev/null 2>&1; then
        log_ok "$label (already applied)"
    else
        git apply --check "$patch_file" || true
        die "Patch failed: ${patch_file##*/}"
    fi
}

assert_file_contains() {
    local file="$1"
    local expected="$2"
    local label="$3"

    require_file "$file" "$label verification target"
    grep -qF -- "$expected" "$file" || die "$label verification failed"
}

assert_file_not_contains() {
    local file="$1"
    local unexpected="$2"
    local label="$3"

    require_file "$file" "$label verification target"
    ! grep -qF -- "$unexpected" "$file" || die "$label verification failed"
}

kernel_patchver() {
    local target_makefile="target/linux/x86/Makefile"

    require_file "$target_makefile" "x86 target Makefile"
    sed -n 's/^KERNEL_PATCHVER:=//p' "$target_makefile" | head -1 | tr -d '[:space:]'
}

patch_hostname_ip() {
    local config_generate="package/base-files/files/bin/config_generate"
    local flash_js="feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/flash.js"

    section "Hostname and IP"

    require_file "$config_generate" "config_generate"
    require_file "$flash_js" "LuCI flash.js"

    sed -i "s/192\\.168\\.[0-9]*\\.[0-9]*/$DEFAULT_IP/g" "$config_generate"

    sed -i "s/, *'immortalwrt\\.lan'//g" "$flash_js"
    sed -i "s/192\\.168\\.[0-9]*\\.[0-9]*/$DEFAULT_IP/g" "$flash_js"
    assert_file_not_contains "$flash_js" "immortalwrt.lan" "LuCI flash reconnect host"
    sed -i "s/hostname='.*'/hostname='$DEVICE_NAME'/g" "$config_generate"

    log_ok "Default IP: $DEFAULT_IP"
    log_ok "Hostname: $DEVICE_NAME"
    log_ok "LuCI flash page reconnects to $DEFAULT_IP"
}

patch_build_version() {
    local apk_cheatsheet="package/base-files/files/etc/profile.d/apk-cheatsheet.sh"
    local banner_file="package/base-files/files/etc/banner"
    local firmware_version="ImmortalWrt ${WRT_BRANCH#openwrt-}-$WRT_DATE"
    local upstream_version="OpenWrt $WRT_VERSION"
    local patchver
    local kernel_version
    local banner_text
    local os_release_file="package/base-files/files/usr/lib/os-release"
    local openwrt_release_file="package/base-files/files/etc/openwrt_release"
    local luci_status_file="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"

    section "Version and Banner"

    if [ -f "$apk_cheatsheet" ]; then
        echo "# Intentionally left empty" > "$apk_cheatsheet"
        log_ok "APK cheatsheet removed"
    fi

    patchver=$(kernel_patchver)
    require_file "target/linux/generic/kernel-$patchver" "kernel version file"
    kernel_version=$(sed -n "s/^LINUX_VERSION-$patchver[[:space:]]*=[[:space:]]*//p" \
        "target/linux/generic/kernel-$patchver" | head -1 | tr -d '[:space:]')
    [ -n "$kernel_version" ] || die "Kernel version not found for ${patchver:-unknown}"
    if [[ "$kernel_version" = .* ]]; then
        kernel_version="${patchver}${kernel_version}"
    fi
    banner_text=" $upstream_version · Kernel $kernel_version"

    require_file "$banner_file" "banner file"
    sed -i "s|^ %D %V, %C.*$|$banner_text|" "$banner_file"
    assert_file_contains "$banner_file" "$banner_text" "Banner"
    log_ok "Banner: ${banner_text# }"

    require_file "$os_release_file" "os-release file"
    sed -i "s#OPENWRT_RELEASE=\"%D %V %C\"#OPENWRT_RELEASE=\"$firmware_version\"#" "$os_release_file"
    assert_file_contains "$os_release_file" "OPENWRT_RELEASE=\"$firmware_version\"" "Firmware version os-release"

    require_file "$openwrt_release_file" "openwrt_release file"
    sed -i "s#DISTRIB_DESCRIPTION='%D %V %C'#DISTRIB_DESCRIPTION='$firmware_version'#" "$openwrt_release_file"
    assert_file_contains "$openwrt_release_file" "DISTRIB_DESCRIPTION='$firmware_version'" "Firmware version openwrt_release"
    log_ok "Firmware version: $firmware_version"

    sed -i "s|luciversion = luciversion.branch + ' ' + luciversion.revision;|luciversion = '$upstream_version';|" \
        "$luci_status_file"
    assert_file_contains "$luci_status_file" "luciversion = '$upstream_version';" "Upstream version"
    log_ok "LuCI version: $upstream_version"
}

patch_x86_cpu_performance() {
    section "X86 CPU Performance"

    apply_source_patch "$PATCH_ROOT/x86/010-kernel-cpufreq-performance.patch" "CPU frequency governor defaults to performance"

    assert_file_contains "config/Config-kernel.in" "default KERNEL_CPU_FREQ_DEFAULT_GOV_PERFORMANCE" "x86 CPU frequency performance"
}

patch_x86_images() {
    local image_makefile="target/linux/x86/image/Makefile"

    section "X86 Images"

    sed -i 's/^    IMAGES-y := rootfs\.img\.gz$/    IMAGES-y :=/' "$image_makefile"

    assert_file_not_contains "$image_makefile" 'IMAGES-y := rootfs.img.gz' "x86 rootfs image skip"
    assert_file_contains "$image_makefile" 'IMAGES-$$(CONFIG_GRUB_EFI_IMAGES) += combined-efi.img.gz' "x86 EFI image"
    log_ok "Standalone rootfs image skipped, EFI image kept"
}

patch_router_ppp() {
    local ppp_proto="package/network/services/ppp/files/ppp.sh"

    section "PPP"

    sed -i 's/\[ "\$(uci get syncdial\.config\.enabled)" -eq "1" \]/[ "$(uci -q get syncdial.config.enabled)" = "1" ]/' "$ppp_proto"

    assert_file_contains "$ppp_proto" '[ "$(uci -q get syncdial.config.enabled)" = "1" ]' "PPPoE syncdial check"
    assert_file_not_contains "$ppp_proto" '[ "$(uci get syncdial.config.enabled)" -eq "1" ]' "PPPoE syncdial check"
    log_ok "PPPoE syncdial check quieted"
}

patch_router_yq() {
    local yq_makefile="feeds/packages/utils/yq/Makefile"
    local yq_tags="GO_PKG_TAGS:=yq_nolua,yq_noini,yq_notoml,yq_noxml,yq_nohcl"

    section "YQ"

    sed -i -e '/^GO_PKG_TAGS:=/d' -e "/^GO_PKG_LDFLAGS_X:=/a $yq_tags" "$yq_makefile"

    assert_file_contains "$yq_makefile" "$yq_tags" "yq build tags"
    log_ok "yq limited to YAML and JSON"
}

patch_imagebuilder() {
    local imagebuilder_makefile="target/imagebuilder/Makefile"

    section "ImageBuilder"

    apply_source_patch "$PATCH_ROOT/imagebuilder/010-standalone-apk-repositories.patch" "Standalone ImageBuilder ships an empty repositories file"

    assert_file_contains "$imagebuilder_makefile" 'touch $(PKG_BUILD_DIR)/repositories' "standalone APK repositories"
}

patch_luci_common() {
    local led_menu_file="feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json"
    local dhcp_file="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/40_dhcp.js"
    local pppoe_file="feeds/luci/protocols/luci-proto-ppp/htdocs/luci-static/resources/protocol/pppoe.js"
    local luci_base_root="feeds/luci/modules/luci-base/root"
    local translations_file="feeds/luci/modules/luci-base/ucode/controller/admin/index.uc"
    local rpcd_luci_file="$luci_base_root/usr/share/rpcd/ucode/luci"

    section "LuCI"

    apply_source_patch "$PATCH_ROOT/luci/010-remove-led-menu.patch" "LED menu removed"
    apply_source_patch "$PATCH_ROOT/luci/020-dhcp-lease-display.patch" "Empty DHCP lease tables hidden"
    apply_source_patch "$PATCH_ROOT/luci/050-pppoe-disable-autofill.patch" "PPPoE credential autofill disabled"
    apply_source_patch "$PATCH_ROOT/luci/060-translations-cache.patch" "Translation catalog cached by the browser"
    apply_source_patch "$PATCH_ROOT/luci/070-cpu-usage-nonblocking.patch" "CPU usage read from /proc/stat"
    apply_source_patch "$PATCH_ROOT/luci/080-root-http-redirect.patch" "Root URL answered with an HTTP redirect to LuCI"
    assert_file_not_contains "$led_menu_file" '"admin/system/leds"' "LuCI LED menu"
    assert_file_contains "$dhcp_file" "return result.length ? E(result) : null;" "LuCI DHCP lease display"
    assert_file_contains "$pppoe_file" "input.setAttribute('autocomplete', autocomplete);" "LuCI PPPoE autocomplete"
    assert_file_contains "$pppoe_file" "setAutocomplete(o, 'off');" "LuCI PPPoE username autocomplete"
    assert_file_contains "$pppoe_file" "setAutocomplete(o, 'new-password');" "LuCI PPPoE password autocomplete"
    assert_file_contains "$translations_file" "public, max-age=31536000, immutable" "LuCI translations cache"
    assert_file_contains "$rpcd_luci_file" "let cpu_stat_prev = [ 0, 0 ];" "LuCI non-blocking CPU usage"
    assert_file_not_contains "$rpcd_luci_file" "top -n1" "LuCI non-blocking CPU usage"
    assert_file_contains "$luci_base_root/usr/share/uhttpd/luci-root-redirect.json" '[ "redirect", "/cgi-bin/luci/" ]' "LuCI root HTTP redirect"
    [ -x "$luci_base_root/etc/uci-defaults/50_luci-uhttpd-root-redirect" ] ||
        die "LuCI root HTTP redirect verification failed"
}

patch_cloud_docker_runtime() {
    local dockerd_makefile="feeds/packages/utils/dockerd/Makefile"
    local dockerd_init="feeds/packages/utils/dockerd/files/dockerd.init"
    local containerd_makefile="feeds/packages/utils/containerd/Makefile"
    local containerd_commands='MAKE_FLAGS += COMMANDS="containerd containerd-shim-runc-v2"'

    section "Docker Runtime"

    apply_source_patch "$PATCH_ROOT/docker/010-dockerd-remove-iptables-deps.patch" "dockerd iptables dependencies removed"
    apply_source_patch "$PATCH_ROOT/docker/020-dockerd-host-mode.patch" "dockerd host mode, bridge option added"
    apply_source_patch "$PATCH_ROOT/docker/030-dockerd-skip-nested-binaries.patch" "dockerd host binary copy skipped"

    if grep -Eq '^[[:space:]]*\+(iptables|iptables-mod-extra|IPV6:ip6tables|IPV6:kmod-ipt-nat6|kmod-ipt-nat|kmod-ipt-physdev)([[:space:]]|\\|$)' "$dockerd_makefile"; then
        die "dockerd dependency cleanup verification failed"
    fi

    if sed -n '/^boot() {/,/^}/p' "$dockerd_init" | grep -q 'uciadd'; then
        die "dockerd host mode boot verification failed"
    fi

    assert_file_contains "$dockerd_init" 'config_get bridge globals bridge ""' "dockerd bridge option"
    assert_file_contains "$dockerd_init" 'json_add_string "bridge" "${bridge}"' "dockerd bridge option"

    sed -i \
        -e '/^STOP=/d' \
        -e '/^SERVICE_STOP_TIME=/d' \
        -e '/^START=99$/a STOP=10' \
        -e '/^START=99$/a SERVICE_STOP_TIME=30' \
        "$dockerd_init"

    assert_file_contains "$dockerd_init" 'STOP=10' "dockerd shutdown order"
    assert_file_contains "$dockerd_init" 'SERVICE_STOP_TIME=30' "dockerd stop timeout"
    log_ok "dockerd stops before disks unmount (STOP=10, 30s timeout)"

    assert_file_contains "$dockerd_makefile" \
        '$(PKG_BUILD_DIR)/hack/make/binary-daemon' "dockerd nested binaries skip"

    sed -i \
        -e 's/^\(  DEPENDS:=$(ARCH_DEPENDS)\) +btrfs-progs +runc$/\1 +runc/' \
        -e 's|/bin/{ctr,containerd,containerd-stress,containerd-shim-runc-v2} |/bin/{containerd,containerd-shim-runc-v2} |' \
        -e '/^MAKE_FLAGS += COMMANDS=/d' \
        -e "/^Build\/Compile=\$(call Build\/Compile\/Default)\$/i $containerd_commands" \
        "$containerd_makefile"

    assert_file_contains "$containerd_makefile" '  DEPENDS:=$(ARCH_DEPENDS) +runc' "containerd btrfs dependency"
    assert_file_contains "$containerd_makefile" '/bin/{containerd,containerd-shim-runc-v2} $(1)/usr/bin/' "containerd install list"
    assert_file_contains "$containerd_makefile" "$containerd_commands" "containerd build commands"
    log_ok "containerd reduced to daemon and runc shim, btrfs dependency dropped"
}

patch_cloud_luci() {
    local ports_file="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/29_ports.js"
    local status_po="feeds/luci/modules/luci-base/po/zh_Hans/base.po"

    section "Cloud LuCI"

    apply_source_patch "$PATCH_ROOT/luci/030-port-status-table.patch" "Port status shown as a table"
    apply_source_patch "$PATCH_ROOT/luci/040-port-status-zh-hans.patch" "Port status zh_Hans translations added"
    assert_file_contains "$ports_file" "No port information available" "LuCI port status table"
    assert_file_contains "$status_po" 'msgid "Speed"' "LuCI port status zh_Hans"
    assert_file_contains "$status_po" 'msgstr "速率"' "LuCI port status zh_Hans"
}

patch_bbrv3() {
    local patch_dir="$PATCH_ROOT/bbrv3"
    local target_patchver="6.12"
    local target_patch_dir="target/linux/generic/backport-$target_patchver"
    local expected_patch_count=20
    local patchver
    local patch_count

    section "BBRv3"

    require_dir "$patch_dir" "BBRv3 patch directory"
    require_dir "target/linux/generic" "OpenWrt generic target directory"

    patchver=$(kernel_patchver)
    [ "$patchver" = "$target_patchver" ] ||
        die "BBRv3 patches support kernel patch version $target_patchver, current target is ${patchver:-unknown}"

    patch_count=$(find "$patch_dir" -maxdepth 1 -type f -name '010-bbr3-*.patch' | wc -l | tr -d '[:space:]')
    [ "$patch_count" -eq "$expected_patch_count" ] ||
        die "Expected $expected_patch_count BBRv3 patches, found $patch_count"

    mkdir -p "$target_patch_dir"
    rm -f "$target_patch_dir"/010-bbr3-*.patch
    cp "$patch_dir"/010-bbr3-*.patch "$target_patch_dir"/

    log_ok "$patch_count patches installed: $target_patch_dir"
}

patch_hostname_ip
patch_build_version
patch_imagebuilder
patch_x86_cpu_performance
patch_x86_images
patch_luci_common

if [ "$BUILD_PROFILE" = "Router" ]; then
    patch_router_ppp
    patch_router_yq
fi

if [ "$BUILD_PROFILE" = "Cloud" ]; then
    patch_cloud_docker_runtime
    patch_cloud_luci
fi

patch_bbrv3
