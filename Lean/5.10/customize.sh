#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: customize.sh
# Description: OpenWrt DIY script (After Update feeds)

# 修改默认IP
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate
# 取消系统默认密码
sed -i "/CYXluq4wUazHjmCDBCqXF/d" package/lean/default-settings/files/zzz-default-settings
# 关闭IPv6 分配长度
sed -i '/ip6assign/d' package/base-files/files/bin/config_generate

# 修改内核版本
sed -i 's/KERNEL_PATCHVER:=5.4/KERNEL_PATCHVER:=5.10/g' ./target/linux/x86/Makefile

# Clone community packages to package/community
mkdir package/community
pushd package/community

# Dockerman
rm -rf ../lean/luci-app-docker
git clone --depth=1 https://github.com/lisaac/luci-app-dockerman
git clone --depth=1 https://github.com/lisaac/luci-lib-docker

#SmartDNS
git clone -b lede --depth=1 https://github.com/pymumu/luci-app-smartdns

popd

# 增加日期显示
pushd package/lean/default-settings/files
export orig_version="$(cat "zzz-default-settings" | grep DISTRIB_REVISION= | awk -F "'" '{print $2}')"
sed -i "s/${orig_version}/${orig_version} ($(date +"%Y-%m-%d"))/g" zzz-default-settings
popd
