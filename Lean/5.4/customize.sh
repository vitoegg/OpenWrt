#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: customize-sta.sh
# Description: OpenWrt DIY script (After Update feeds)
#

# 旁路由相关Lan设置
cat >$NETIP <<-EOF
uci set network.lan.ipaddr='192.168.10.2'               # IPv4 地址(openwrt后台地址)
uci set network.lan.netmask='255.255.255.0'             # IPv4 子网掩码
uci set network.lan.gateway='192.168.10.1'              # IPv4 网关
uci set network.lan.dns='192.168.10.1'                  # DNS(多个DNS要用空格分开)
uci set network.lan.delegate='0'                        # 去掉LAN口使用内置的 IPv6 管理
uci commit network                                      # 不要删除跟注释,除非上面全部删除或注释掉了
uci set dhcp.lan.ignore='1'                             # 关闭DHCP功能
uci commit dhcp                                         # 跟‘关闭DHCP功能’联动,同时启用或者删除跟注释
EOF

# 修改内核版本
#sed -i 's/KERNEL_PATCHVER:=5.10/KERNEL_PATCHVER:=5.4/g' ./target/linux/x86/Makefile

# 取消系统默认密码
sed -i "/CYXluq4wUazHjmCDBCqXF/d" package/lean/default-settings/files/zzz-default-settings
# 关闭IPv6 分配长度
sed -i '/ip6assign/d' package/base-files/files/bin/config_generate

# Clone community packages to package/community
mkdir package/community
pushd package/community

# Dockerman
rm -rf ../lean/luci-app-docker
git clone --depth=1 https://github.com/lisaac/luci-app-dockerman
git clone --depth=1 https://github.com/lisaac/luci-lib-docker

popd

# 增加日期显示
pushd package/lean/default-settings/files
export orig_version="$(cat "zzz-default-settings" | grep DISTRIB_REVISION= | awk -F "'" '{print $2}')"
sed -i "s/${orig_version}/${orig_version} ($(date +"%Y-%m-%d"))/g" zzz-default-settings
popd
