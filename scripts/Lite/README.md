# OpenWrt Enhanced by Pmkol
This project uses automatically built extended software repositories, optimizing official packages and adding commonly used ones not included in the official source.

### Special Thanks
- [OpenWrt-Lite from Pmkol](https://github.com/pmkol/openwrt-lite)

### Supported Hardware:
- [x] X86_64


### Features:
- Optimized Linux Kernel 6.11.11
  - [x] Full cone NAT
  - [x] TCP BBRv3
  - [x] TCP Brutal
  - [x] LLVM-BPF
  - [x] Shortcut-FE
  - [x] Multipath TCP
- Fixed kernel and drivers to production-verified stable versions
- Optimized toolchain and compilation parameters for better performance
- Built-in extended OpenWrt software repositories
- Bash shell with command completion by default
- Lightweight integration of commonly used packages with bug fixes


### Upgrade Instructions:
- Package Upgrade (Recommended)

  In most cases, you can upgrade packages online:
  ```
  WARNING: Do NOT upgrade these system packages:
  luci-base | luci-mod-network | luci-mod-status | luci-mod-system
  ```

  System -> Scheduled Tasks

  ```
  0 5 * * * opkg update && opkg list-upgradable | grep -vE "(luci-base|luci-mod-)" | awk '{print $1}' | xargs opkg upgrade
  ```

- Firmware Upgrade

  System -> Backup / Flash Firmware

### Changelog:

#### Build System & Workflows
- Removed unnecessary workflows and configs (.github/workflows/build-openwrt-*.yml, openwrt/*.config)
- Changed hostname from OpenWrt to HomeLab (openwrt/scripts/06-custom.sh)
- Increased root filesystem partition size from 944MB to 1065MB (openwrt/23-config-musl-x86)
- Use file replacement method to preset software configuration (openwrt/scripts/00-prepare_base.sh)

#### Network Configuration
- Changed default LAN IP from 10.0.0.1 to 192.168.10.1 (openwrt/build.sh)
- Replaced hardcoded sensitive information with environment variables (ROOT_PASSWORD_HASH, PPPOE_USERNAME, PPPOE_PASSWORD, PPPOE_MAC,  OPENCLASH_CONFIG_URL) (openwrt/scripts/06-custom.sh)
- Added static DHCP configuration for common devices (openwrt/scripts/06-custom.sh)
- Disabled IPv6 by default for better compatibility (openwrt/scripts/06-custom.sh)

#### Performance Optimization
- Changed CPU mode to performance for better throughput (openwrt/scripts/06-custom.sh)
- Added CAKE qdisc for improved network performance (openwrt/23-config-common-lite)

#### Applications & Services
- Added OpenClash with pre-downloaded core files and configuration (openwrt/23-config-common-custom, openwrt/scripts/06-custom.sh)
- Added AdGuardHome with pre-downloaded binary (openwrt/23-config-common-custom, openwrt/scripts/06-custom.sh)
- Customized Argon theme with new background (openwrt/scripts/06-custom.sh)
- Removed unnecessary packages (openwrt/23-config-common-custom, openwrt/23-config-common-lite)