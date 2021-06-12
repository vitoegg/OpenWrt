# OpenWrt

##### 基于OpenWrt-Actions-Lean-自动化在线编译脚本  

1. [Fork仓库](https://github.com/db-one/OpenWrt-AutoBuild)

2. [Dockerman编译参考](https://github.com/SuLingGG/OpenWrt-Rpi/blob/main/scripts/lean-openwrt.sh)



##### 主要 Luci App

|              LuCI APP              |              用途               |
| :--------------------------------  | :----------------------------- |
|       luci-app-openclash       |          clash客户端           |
|           luci-app-dockerman           |      docker可视化管理      |
|          luci-app-samba          |      文件服务器       |
|        luci-app-hd-idle        |       硬盘休眠      |
|        luci-app-diskman        |    磁盘管理工具     |
|      luci-app-flowoffload      |            转发加强工具            |



##### 源码和脚本来自

- [Lean](https://github.com/coolsnowwolf/lede)
- [P3TERX](https://github.com/P3TERX/Actions-OpenWrt)



##### 核心插件来自

- [OpenClash](https://github.com/vernesong/OpenClash.git)
- [Dockerman(含依赖版)](https://github.com/KFERMercer/luci-app-dockerman)
- [Docker源码](https://github.com/lisaac/luci-app-docker)
- [Docker依赖](https://github.com/lisaac/luci-lib-docker)
