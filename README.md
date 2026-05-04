<p align="center">
  <img src="https://raw.githubusercontent.com/vitoegg/Provider/master/Picture/Banner.webp" alt="OpenWrt Builder" width="100%">
</p>

> [!TIP]
> 本项目基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 的定制，使用 `GitHub Actions` 自动化编译，通过内置 `files` 实现 `Nikki`, `MosDNS`, `Dockerman`, `Mio`, `Samba4` 开箱即用。

```
OpenWrt/
|
├── Router & Cloud/
│   ├── Config/
│   │   ├── General.txt            # 通用系统配置
│   │   └── Custom.txt             # 用户自定义应用
│   └── Scripts/
│       ├── Prepare.sh             # 编译环境准备脚本
│       ├── Packages.sh            # 软件包管理脚本
│       ├── Patch.sh               # 系统优化补丁脚本
│       └── Settings.sh            # 系统预设脚本
|
├── .github/workflows/
│   ├── build-router-firmware.yml  # Router 版本构建
│   ├── build-cloud-firmware.yml   # Cloud 版本构建
│   └── update-rclone-config.yml   # Rclone 配置更新
|
└── README.md
```

#### 💖 项目参考

<div align="center">
  <table width="100%">
    <tr>
      <td align="center" width="320">
        <br>
        <a href="https://github.com/immortalwrt/immortalwrt">
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
