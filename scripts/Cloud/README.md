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