#!/bin/bash

# 安装额外依赖软件包
# sudo -E apt-get -y install rename

# 更新feeds文件
# sed -i 's@#src-git helloworld@src-git helloworld@g' feeds.conf.default #启用helloworld
cat feeds.conf.default

# 添加第三方软件包
git clone https://github.com/vernesong/OpenClash.git -b master package/clash
git clone https://github.com/KFERMercer/luci-app-dockerman package/docker
git clone https://github.com/lisaac/luci-lib-docker package/docker

# 更新并安装源
./scripts/feeds clean
./scripts/feeds update -a && ./scripts/feeds install -a

# 删除部分默认包
rm -rf package/lean/luci-app-docker


# 自定义定制选项
ZZZ="package/lean/default-settings/files/zzz-default-settings"
#
sed -i 's#192.168.1.1#192.168.10.1#g' package/base-files/files/bin/config_generate            # 定制默认IP
sed -i 's@.*CYXluq4wUazHjmCDBCqXF*@#&@g' $ZZZ                                             # 取消系统默认密码
sed -i "/uci commit system/i\uci set system.@system[0].hostname='OpenWrt'" $ZZZ       # 修改主机名称为OpenWrt
sed -i "s/OpenWrt / $(TZ=UTC-8 date "+%Y.%m.%d") @ OpenWrt /g" $ZZZ              # 增加自己个性名称
# sed -i 's/PATCHVER:=5.4/PATCHVER:=4.19/g' target/linux/x86/Makefile                     # 修改内核版本为4.19
# sed -i "/uci commit luci/i\uci set luci.main.mediaurlbase=/luci-static/atmaterial_red" $ZZZ        # 设置默认主题(如果编译可会自动修改默认主题的，有可能会失效)

# ================================================
#sed -i 's#%D %V, %C#%D %V, %C Lean_x86_64#g' package/base-files/files/etc/banner               # 自定义banner显示

#创建自定义配置文件 - Lean_x86_64

cd build/Lean_x86_64
touch ./.config

#
# ========================固件定制部分========================
# 

# 
# 如果不对本区块做出任何编辑, 则生成默认配置固件. 
# 

# 以下为定制化固件选项和说明:
#

#
# 有些插件/选项是默认开启的, 如果想要关闭, 请参照以下示例进行编写:
# 
#          =========================================
#         |  # 取消编译VMware镜像:                    |
#         |  cat >> .config <<EOF                   |
#         |  # CONFIG_VMDK_IMAGES is not set        |
#         |  EOF                                    |
#          =========================================
#

# 
# 以下是一些提前准备好的一些插件选项.
# 直接取消注释相应代码块即可应用. 不要取消注释代码块上的汉字说明.
# 如果不需要代码块里的某一项配置, 只需要删除相应行.
#
# 如果需要其他插件, 请按照示例自行添加.
# 注意, 只需添加依赖链顶端的包. 如果你需要插件 A, 同时 A 依赖 B, 即只需要添加 A.
# 
# 无论你想要对固件进行怎样的定制, 都需要且只需要修改 EOF 回环内的内容.
# 

# 编译x64固件:
cat >> .config <<EOF
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_Generic=y
EOF

# 设置固件大小:
cat >> .config <<EOF
CONFIG_TARGET_KERNEL_PARTSIZE=32
CONFIG_TARGET_ROOTFS_PARTSIZE=870
EOF

# 固件压缩:
cat >> .config <<EOF
CONFIG_TARGET_IMAGES_GZIP=y
EOF

# 编译UEFI固件:
cat >> .config <<EOF
CONFIG_EFI_IMAGES=y
EOF


# 第三方插件选择:
cat >> .config <<EOF
CONFIG_PACKAGE_luci-app-openclash=y #OpenClash客户端
CONFIG_PACKAGE_luci-app-dockerman=y #dockerman客户端
EOF

# ShadowsocksR插件:
cat >> .config <<EOF
CONFIG_PACKAGE_luci-app-ssr-plus=n
EOF

# 常用LuCI插件:
cat >> .config <<EOF
CONFIG_PACKAGE_luci-app-adbyby-plus=n #adbyby去广告
CONFIG_PACKAGE_luci-app-webadmin=n #Web管理页面设置
CONFIG_PACKAGE_luci-app-ddns=n #DDNS服务
CONFIG_DEFAULT_luci-app-vlmcsd=n #KMS激活服务器
CONFIG_PACKAGE_luci-app-filetransfer=n #系统-文件传输
CONFIG_PACKAGE_luci-app-autoreboot=n #定时重启
CONFIG_PACKAGE_luci-app-upnp=n #通用即插即用UPnP(端口自动转发)
CONFIG_PACKAGE_luci-app-accesscontrol=n #上网时间控制
CONFIG_PACKAGE_luci-app-arpbind=n #IP/Mac绑定
CONFIG_PACKAGE_luci-app-wol=n #网络唤醒
CONFIG_PACKAGE_luci-app-frpc=n #Frp内网穿透
CONFIG_PACKAGE_luci-app-nlbwmon=n #宽带流量监控
CONFIG_PACKAGE_luci-app-wrtbwmon=n #实时流量监测
CONFIG_PACKAGE_luci-app-sfe=n #高通开源的 Shortcut FE 转发加速引擎
CONFIG_PACKAGE_luci-app-ttyd=y #高通开源的 Shortcut FE 转发加速引擎
CONFIG_PACKAGE_luci-app-flowoffload=y #开源 Linux Flow Offload 驱动
CONFIG_PACKAGE_luci-app-haproxy-tcp=n #Haproxy负载均衡
CONFIG_PACKAGE_luci-app-diskman=y #磁盘管理磁盘信息
CONFIG_PACKAGE_luci-app-transmission=n #TR离线下载
CONFIG_PACKAGE_luci-app-qbittorrent=n #QB离线下载
CONFIG_PACKAGE_luci-app-amule=n #电驴离线下载
CONFIG_PACKAGE_luci-app-xlnetacc=n #迅雷快鸟
CONFIG_PACKAGE_luci-app-zerotier=n #zerotier内网穿透
CONFIG_PACKAGE_luci-app-hd-idle=y #磁盘休眠
CONFIG_PACKAGE_luci-app-unblockmusic=n #解锁网易云灰色歌曲
CONFIG_PACKAGE_luci-app-vlmcsd=n #kms服务器
CONFIG_PACKAGE_luci-app-airplay2=n #Apple AirPlay2音频接收服务器
CONFIG_PACKAGE_luci-app-music-remote-center=n #PCHiFi数字转盘遥控
CONFIG_PACKAGE_luci-app-usb-printer=n #USB打印机
CONFIG_PACKAGE_luci-app-sqm=n #SQM智能队列管理
CONFIG_PACKAGE_luci-app-jd-dailybonus=n #京东签到服务
CONFIG_PACKAGE_luci-app-uugamebooster=n #UU游戏加速器


# LuCI主题:
cat >> .config <<EOF
CONFIG_PACKAGE_luci-theme-netgear=y
EOF


# 
# ========================固件定制部分结束========================
# 


sed -i 's/^[ \t]*//g' ./.config

# 返回工作目录
cd ../..

# 配置文件创建完成
