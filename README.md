<p align="center">
  <img src="https://raw.githubusercontent.com/vitoegg/Provider/master/Picture/Banner.webp" alt="OpenWrt Builder" width="100%">
</p>

> [!TIP]
> 本项目基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 的定制，使用 `GitHub Actions` 自动化编译，通过内置 `files` 实现 `Nikki`, `MosDNS`, `Docker`, `Mio`, `Samba4` 开箱即用。

```
OpenWrt/
|
├── scripts/
│   ├── build.sh                        # 构建入口，对应 workflow 的每个步骤
│   ├── lib/                            # 公共函数与 GHCR 操作
│   ├── customize/                      # 定制源码树：包、文件、补丁、设置、配置
│   └── artifacts/                      # ImageBuilder、缓存、SDK 的发布与恢复
|
├── patches/                            # 源码补丁
|
├── profiles/
│   ├── upstream.conf                   # 上游仓库与版本锁定
│   ├── feeds.conf                      # Feeds 锁定
│   ├── common/build.config             # 公共编译配置
│   ├── router/                         # Router 编译配置与设备配置
│   └── cloud/                          # Cloud 编译配置与设备配置
|
├── .github/workflows/
│   ├── build-immortalwrt-firmware.yml  # 固件构建
│   ├── refresh-bbr-patches.yml         # BBR 补丁更新
│   └── update-rclone-config.yml        # Rclone 配置更新
|
└── README.md
```

#### 💖 项目参考

<div align="center">
  <table width="100%">
    <tr>
      <td align="center" width="320">
        <br>
        <a href="https://github.com/immortalwrt/immortalwrt/tree/openwrt-25.12">
          <img src="https://github.com/immortalwrt.png?size=120" width="40" height="40" alt="ImmortalWrt"><br>
          ImmortalWrt
        </a>
        <br>
        <br>
      </td>
      <td align="center" width="320">
        <br>
        <a href="https://github.com/nikkinikki-org/OpenWrt-nikki">
          <img src="https://github.com/nikkinikki-org.png?size=120" width="40" height="40" alt="Nikki"><br>
          Nikki
        </a>
        <br>
        <br>
      </td>
      <td align="center" width="320">
        <br>
        <a href="https://github.com/sbwml/luci-app-mosdns">
          <img src="https://github.com/sbwml.png?size=120" width="40" height="40" alt="MosDNS"><br>
          MosDNS
        </a>
        <br>
        <br>
      </td>
    </tr>
    <tr>
      <td align="center" width="320">
        <br>
        <a href="https://github.com/jerrykuku/luci-theme-argon">
          <img src="https://github.com/jerrykuku.png?size=120" width="40" height="40" alt="Argon"><br>
          Argon
        </a>
        <br>
        <br>
      </td>
      <td align="center" width="320">
        <br>
        <a href="https://github.com/lisaac/luci-app-dockerman">
          <img src="https://github.com/lisaac.png?size=120" width="40" height="40" alt="Dockerman"><br>
          Dockerman
        </a>
        <br>
        <br>
      </td>
      <td align="center" width="320">
        <br>
        <a href="https://github.com/vitoegg/Mio">
          <img src="https://github.com/vitoegg.png?size=120" width="40" height="40" alt="Mio"><br>
          Mio
        </a>
        <br>
        <br>
      </td>
    </tr>
  </table>
</div>
