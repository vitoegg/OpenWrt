# OpenWrt

#### 基于OpenWrt-Actions-Lean-自动化在线编译脚本  

1. [Fork仓库](https://github.com/db-one/OpenWrt-AutoBuild)

2. [Dockerman编译参考](https://github.com/SuLingGG/OpenWrt-Rpi/blob/main/scripts/lean-openwrt.sh)


####主要 Luci App

|              LuCI APP              |              用途               |
| :--------------------------------  | :----------------------------- |
|       luci-app-accesscontrol       |          上网时间控制           |
|           luci-app-acme            |      Acme.sh HTTP 证书申请      |
|          luci-app-adblock          |      ADBlock 广告屏蔽工具       |
|        luci-app-adbyby-plus        |       ADBYBY 广告屏蔽大师       |
|        luci-app-adguardhome        |    ADGuardHome 广告屏蔽工具     |
|      luci-app-advanced-reboot      |            高级重启             |
|      luci-app-advancedsetting      |          系统高级设置           |
|           luci-app-ahcp            |           AHCP 服务器           |
|         luci-app-airplay2          |     AirPlay2 音频推送服务器     |
|          luci-app-airwhu           |     锐捷 802.1X 认证客户端      |
|          luci-app-aliddns          |           阿里云 DDNS           |
|           luci-app-amule           |       aMule P2P 下载工具        |
|         luci-app-appfilter         |            应用过滤             |
|       luci-app-argon-config        |         Argon 主题配置          |
|           luci-app-aria2           |         Aria2 下载工具          |
|          luci-app-arpbind          |           IP/Mac 绑定           |
|    luci-app-attendedsysupgrade     |         参与式系统升级          |
|      luci-app-autoipsetadder       |           IPSET 配置            |
|        luci-app-autoreboot         |            定时重启             |


##### 源码和脚本来自

- [Lean](https://github.com/coolsnowwolf/lede)
- [P3TERX](https://github.com/P3TERX/Actions-OpenWrt)

##### 核心插件来自

- [OpenClash](https://github.com/vernesong/OpenClash.git)
- [Dockerman(含依赖版)](https://github.com/KFERMercer/luci-app-dockerman)
- [Docker源码](https://github.com/lisaac/luci-app-docker)
- [Docker依赖](https://github.com/lisaac/luci-lib-docker)
