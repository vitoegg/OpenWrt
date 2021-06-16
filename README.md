# OpenWrt

##### 基于OpenWrt-Actions-Lean-自动化在线编译自用固件  

编译脚本参考：

1. [DB-ONE](https://github.com/db-one/OpenWrt-AutoBuild)

2. [Dockerman修改版编译参考](https://github.com/SuLingGG/OpenWrt-Rpi/blob/main/scripts/lean-openwrt.sh)

3. [Dockerman原版编译参考](https://github.com/mingxiaoyu/N1Openwrt/blob/master/diy.sh)


##### 1. 主要App


|              LuCI APP              |              用途               |
| :--------------------------------  | :----------------------------- |
|       luci-app-openclash       |          clash客户端           |
|           luci-app-dockerman           |      docker可视化管理      |
|          luci-app-samba          |      文件服务器       |
|        luci-app-hd-idle        |       硬盘休眠      |
|        luci-app-diskman        |    磁盘管理工具     |
|      luci-app-flowoffload      |            转发加强工具            |



##### 2. 源码和脚本来自


- [Lean](https://github.com/coolsnowwolf/lede)
- [P3TERX](https://github.com/P3TERX/Actions-OpenWrt)
- [Telegram Bot](https://github.com/appleboy/telegram-action)



##### 3. 核心插件来自

- [OpenClash](https://github.com/vernesong/OpenClash.git)
- [Dockerman(修改版)](https://github.com/KFERMercer/luci-app-dockerman)
- [Dockerman](https://github.com/lisaac/luci-app-docker)
