# OpenLite

基于OpenWrt的定制化项目，用于日常设备的固件编译。

```
OpenLite/
├── files/                                      # [预设文件]
│   ├── Pictures/                               # 主题背景图片
│   ├── cpuinfo                                 # CPU信息展示脚本
│   ├── packages                                # 预安装包列表
│   └── README.md                               # 编译依赖说明
├── scripts/                                    # [脚本集合]
│   ├── Lite/                                   # Lite构建脚本
│   │   ├── 06-custom.sh                        # 自定义配置脚本
│   │   ├── 23-config-musl-x86                  # x86架构配置
│   │   ├── 23-config-common-lite               # 通用轻量级配置
│   │   └── 23-config-common-custom             # 用户自定义配置
│   ├── Router/                                 # Router构建脚本
│   │   ├── build.sh                            # 路由器固件构建脚本
│   │   ├── .config                             # 路由器配置文件
│   │   └── feeds.sh                            # 软件源配置脚本
│   └── Cloud/                                  # Cloud构建脚本
│       ├── build.sh                            # 云服务器固件构建脚本
│       ├── .config                             # 云服务器配置文件
│       └── feeds.sh                            # 软件源配置脚本
```

#### 1. 适配硬件
- X86_64架构设备

#### 2. 核心应用
- [x] **OpenClash**：强大的代理工具，预下载核心文件和配置
- [x] **AdGuardHome**：网络广告和跟踪拦截器，预下载二进制文件
- [x] **MosDNS**：DNS分流工具，用于分流不同网站使用的上游DNS

#### 3. 特别感谢
- [OpenWrt Lite](https://github.com/pmkol/openwrt-lite)

- [OpenWrt Lean](https://github.com/coolsnowwolf/lede)

- [P3TERX](https://p3terx.com)