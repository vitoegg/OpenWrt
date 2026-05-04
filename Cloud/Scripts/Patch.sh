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

patch_hostname_and_ip() {
    local config_generate="package/base-files/files/bin/config_generate"
    local flash_js

    section "Hostname and IP"

    require_file "$config_generate" "config_generate"

    log "Setting default IP to 192.168.10.2"
    sed -i 's/192\.168\.[0-9]*\.[0-9]*/192.168.10.2/g' "$config_generate"

    log "Modifying immortalwrt.lan redirect IP"
    flash_js=$(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" 2>/dev/null)
    if [ -n "$flash_js" ] && [ -f "$flash_js" ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/192.168.10.2/g' "$flash_js"
        log "LuCI flash redirect IP patched"
    else
        log "Warning: LuCI flash.js not found, skipping redirect IP patch"
    fi

    log "Modifying hostname to HomeCloud"
    sed -i "s/hostname='.*'/hostname='HomeCloud'/g" "$config_generate"
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

patch_dockerman_menu() {
    local menu_file="feeds/luci/applications/luci-app-dockerman/root/usr/share/luci/menu.d/luci-app-dockerman.json"
    local common_js="feeds/luci/applications/luci-app-dockerman/htdocs/luci-static/resources/dockerman/common.js"
    local tmp_file

    log "Patching Dockerman JS menu"

    require_file "$menu_file" "Dockerman JS menu file"
    require_file "$common_js" "Dockerman JS common file"

    tmp_file=$(mktemp)
    jq '
        with_entries(.key |= sub("^admin/services/dockerman"; "admin/docker"))
        | with_entries(
            if .value.action.path? then
                .value.action.path |= sub("^admin/services/dockerman"; "admin/docker")
            else
                .
            end
        )
        | ."admin/docker".title = "Docker"
        | ."admin/docker".order = 40
        | ."admin/docker/overview".order = 2
        | ."admin/docker/containers".order = 3
        | ."admin/docker/images".order = 4
        | ."admin/docker/networks".order = 5
        | ."admin/docker/volumes".order = 6
        | ."admin/docker/events".order = 7
        | ."admin/docker/configuration".order = 8
    ' "$menu_file" > "$tmp_file"
    mv "$tmp_file" "$menu_file"

    perl -0pi -e 's#admin/services/dockerman#admin/docker#g' "$common_js"

    if grep -R "admin/services/dockerman\|services/dockerman" \
        feeds/luci/applications/luci-app-dockerman >/dev/null; then
        log "ERROR: old Dockerman menu path still exists"
        exit 1
    fi

    log "Dockerman JS menu moved to admin/docker"
}

patch_dockerd_host_mode() {
    local dockerd_init="feeds/packages/utils/dockerd/files/dockerd.init"

    section "Docker Host Mode"

    require_file "$dockerd_init" "dockerd init script"

    log "Disabling dockerd boot-time docker0 UCI creation"
    perl -0pi -e 's/boot\(\) \{\n\s*uciadd\n\s*rc_procd start_service\n\}/boot() {\n\trc_procd start_service\n}/' "$dockerd_init"
    if sed -n '/^boot() {/,/^}/p' "$dockerd_init" | grep -q 'uciadd'; then
        log "ERROR: dockerd boot function pattern not found"
        exit 1
    fi

    log "Adding dockerd UCI bridge option support"
    if ! grep -q 'local .*bridge' "$dockerd_init"; then
        perl -0pi -e 's/local alt_config_file data_root log_level iptables ip6tables bip/local alt_config_file data_root log_level iptables ip6tables bip bridge/' "$dockerd_init"
    fi

    if ! grep -q 'config_get bridge globals bridge ""' "$dockerd_init"; then
        perl -0pi -e 's/^([ \t]*)config_get bip globals bip ""\n/${1}config_get bip globals bip ""\n${1}config_get bridge globals bridge ""\n/m' "$dockerd_init"
    fi

    if ! grep -q 'json_add_string "bridge" "${bridge}"' "$dockerd_init"; then
        perl -0pi -e 's/^([ \t]*)\[ -z "\$\{bip\}" \] \|\| json_add_string "bip" "\$\{bip\}"\n/${1}[ -z "\${bip}" ] || json_add_string "bip" "\${bip}"\n${1}[ -z "\${bridge}" ] || json_add_string "bridge" "\${bridge}"\n/m' "$dockerd_init"
    fi

    sed -n '/^boot() {/,/^}/p' "$dockerd_init" | grep -q 'rc_procd start_service'
    grep -q 'config_get bridge globals bridge ""' "$dockerd_init"
    grep -q 'json_add_string "bridge" "${bridge}"' "$dockerd_init"
    log "dockerd host-mode patch applied successfully"
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

patch_port_status_table() {
    local ports_file="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/29_ports.js"

    log "Replacing LuCI port status cards with text table"

    require_file "$ports_file" "port status patch target file"

    cat > "$ports_file" <<'PORTS_JS'
'use strict';
'require baseclass';
'require fs';
'require uci';
'require rpc';
'require network';

const callGetBuiltinEthernetPorts = rpc.declare({
	object: 'luci',
	method: 'getBuiltinEthernetPorts',
	expect: { result: [] }
});

function collectBoardPorts(board) {
	const ports = [];

	if (!L.isObject(board) || !L.isObject(board.network))
		return ports;

	for (let role of [ 'lan', 'wan' ]) {
		const net = board.network[role];

		if (!L.isObject(net))
			continue;

		if (Array.isArray(net.ports)) {
			for (let device of net.ports)
				ports.push({ role, device });
		}
		else if (typeof(net.device) == 'string') {
			ports.push({ role, device: net.device });
		}
	}

	return ports;
}

function formatSpeed(carrier, speed) {
	if (!carrier || speed == null || speed <= 0)
		return '-';

	return '%d Mb/s'.format(speed);
}

function formatDuplex(carrier, duplex) {
	if (!carrier || !duplex)
		return '-';

	if (duplex == 'full')
		return _('Full Duplex');

	if (duplex == 'half')
		return _('Half Duplex');

	return duplex;
}

return baseclass.extend({
	title: _('Port status'),

	load() {
		return Promise.all([
			L.resolveDefault(callGetBuiltinEthernetPorts(), []),
			L.resolveDefault(fs.read('/etc/board.json'), '{}'),
			network.getNetworks(),
			uci.load('network')
		]);
	},

	render(data) {
		if (L.hasSystemFeature('swconfig'))
			return null;

		const board = JSON.parse(data[1] || '{}');
		let known_ports = [];

		if (Array.isArray(data[0]) && data[0].length > 0)
			known_ports = data[0].map(port => ({ ...port }));
		else
			known_ports = collectBoardPorts(board);

		known_ports = known_ports
			.filter(port => port && port.device)
			.map(port => ({ ...port, netdev: network.instantiateDevice(port.device) }))
			.sort((a, b) => L.naturalCompare(a.device, b.device));

		const table = E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Port')),
				E('th', { 'class': 'th' }, _('Status')),
				E('th', { 'class': 'th' }, _('Speed')),
				E('th', { 'class': 'th' }, _('Duplex'))
			])
		]);

		cbi_update_table(table, known_ports.map(port => {
			const carrier = port.netdev.getCarrier();

			return [
				port.netdev.getName(),
				carrier ? _('Connected') : _('No link'),
				formatSpeed(carrier, port.netdev.getSpeed()),
				formatDuplex(carrier, port.netdev.getDuplex())
			];
		}), E('em', _('No port information available')));

		return E([ table ]);
	}
});
PORTS_JS

    log "LuCI port status table patch applied successfully"
}

patch_status_translations() {
    local status_po="feeds/luci/modules/luci-base/po/zh_Hans/base.po"
    local status_po_result

    log "Patching LuCI port status zh_Hans translations"

    if [ ! -f "$status_po" ]; then
        log "Warning: LuCI base zh_Hans translation file not found, skipping translations"
        return
    fi

    log "Using LuCI status translation file: $status_po"
    status_po_result=$(python3 - "$status_po" <<'PY'
from pathlib import Path
import re
import sys

target = Path(sys.argv[1])
translations = {
    "Speed": "速率",
    "Duplex": "双工",
    "Full Duplex": "全双工",
    "Half Duplex": "半双工",
}

text = target.read_text()
changed = False

def po_quote(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

for msgid, msgstr in translations.items():
    entry = f"msgid {po_quote(msgid)}\nmsgstr {po_quote(msgstr)}"
    pattern = re.compile(
        r'^msgid ' + re.escape(po_quote(msgid)) + r'\nmsgstr "(?:[^"\\]|\\.)*"$',
        re.M
    )

    if pattern.search(text):
        updated = pattern.sub(entry, text, count=1)
        changed = changed or updated != text
        text = updated
    else:
        text = text.rstrip() + "\n\n" + entry + "\n"
        changed = True

if changed:
    target.write_text(text)
    print("PATCHED")
else:
    print("UNCHANGED")
PY
)

    if [ "$status_po_result" = "PATCHED" ]; then
        log "LuCI port status zh_Hans translations patched successfully"
    else
        log "LuCI port status zh_Hans translations already patched"
    fi
}

patch_mio_menu() {
    local mio_menu_file

    log "Customizing Mio LuCI menu for VPN"

    mio_menu_file=$(find package feeds -path '*/root/usr/share/luci/menu.d/luci-app-mio.json' -print -quit 2>/dev/null || true)
    if [ -z "$mio_menu_file" ]; then
        log "ERROR: luci-app-mio menu file not found"
        exit 1
    fi

    if grep -q '"admin/services/mio"' "$mio_menu_file"; then
        sed -i 's#"admin/services/mio"#"admin/vpn/mio"#' "$mio_menu_file"
        log "Mio menu migration applied successfully"
    elif grep -q '"admin/vpn/mio"' "$mio_menu_file"; then
        log "Mio menu migration already applied"
    else
        log "ERROR: Mio menu key not found in $mio_menu_file"
        exit 1
    fi
}

patch_luci_menu_and_status() {
    section "LuCI Menu and Status"

    patch_dockerman_menu
    patch_mio_menu
    patch_luci_led_menu
    patch_dhcp_lease_display
    patch_port_status_table
    patch_status_translations
}

main() {
    patch_hostname_and_ip
    patch_build_version_and_banner
    patch_cpu_performance
    patch_dockerd_host_mode
    patch_luci_menu_and_status

    log "Patch.sh completed"
}

main "$@"
