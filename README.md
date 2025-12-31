# OpenWrt

基于 [OpenWrt-Lite](https://github.com/pmkol/openwrt-lite) 的定制化项目，提供 **Lite** 和 **Cloud** 两个版本的固件编译方案。

```
OpenWrt/
├── files/                                      # [预设文件]
│   ├── Picture/                                # 主题背景图片
│   ├── packages                                # 编译依赖包列表
│   └── README.md                               # 编译依赖说明
├── scripts/                                    # [脚本集合]
│   ├── Lite/                                   # Lite版本构建脚本
│   │   ├── 06-custom.sh                        # 自定义配置脚本
│   │   ├── 23-config-musl-x86                  # x86架构配置
│   │   ├── 23-config-common-lite               # 通用轻量级配置
│   │   ├── 23-config-common-custom             # 用户自定义配置
│   │   └── README.md                           # 说明文档
│   └── Cloud/                                  # Cloud版本构建脚本
│       ├── 06-custom.sh                        # 自定义配置脚本
│       ├── 23-config-musl-x86                  # x86架构配置
│       ├── 23-config-common-server             # 服务器通用配置
│       ├── 23-config-common-custom             # 用户自定义配置
│       └── README.md                           # 说明文档
```

#### 1. 适配硬件
- X86_64 架构设备

#### 2. 内核特性
- [x] Linux Kernel 6.11
- [x] Full Cone NAT
- [x] TCP BBRv3
- [x] TCP Brutal
- [x] LLVM-BPF
- [x] Shortcut-FE
- [x] Multipath TCP
- [x] CAKE QoS

#### 3. Lite 版本（路由网关）
| 应用 | 说明 |
|------|------|
| **Nikki** | Mihomo 代理工具，预下载 zashboard UI |
| **MosDNS** | DNS 分流工具，预下载分流规则 |

#### 4. Cloud 版本（云服务器）
| 应用 | 说明 |
|------|------|
| **Docker** | 容器管理平台 |
| **Samba4** | 文件共享服务 |
| **Shadowsocks-libev** | 代理服务端 |
| **DDNS** | 动态域名解析脚本 |

#### 5. 特别感谢
- [OpenWrt Lite](https://github.com/pmkol/openwrt-lite)
- [OpenWrt Lean](https://github.com/coolsnowwolf/lede)
- [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)
- [Mihomo Smart Core](https://github.com/vernesong/OpenClash/releases/tag/mihomo)
- [MosDNS](https://github.com/sbwml/luci-app-mosdns)
- [P3TERX](https://p3terx.com)
