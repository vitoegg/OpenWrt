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
sed -i 's/192.168.1.1/192.168.10.2/g' package/base-files/files/bin/config_generate
# 取消系统默认密码
sed -i "/CYXluq4wUazHjmCDBCqXF/d" package/lean/default-settings/files/zzz-default-settings
# 关闭IPv6 分配长度
sed -i '/ip6assign/d' package/base-files/files/bin/config_generate
#修改时间格式
sed -i 's#localtime  = os.date()#localtime  = os.date("%Y年%m月%d日") .. " " .. translate(os.date("%A")) .. " " .. os.date("%X")#g' package/lean/autocore/files/*/index.htm
# 停止监听443端口
sed -i 's@list listen_https@# list listen_https@g' package/network/services/uhttpd/files/uhttpd.config

# 修改内核版本
#sed -i 's/KERNEL_PATCHVER:=5.15/KERNEL_PATCHVER:=5.10/g' ./target/linux/x86/Makefile

# 添加Build日期
pushd package/lean/default-settings/files
export orig_version="$(cat "zzz-default-settings" | grep DISTRIB_REVISION= | awk -F "'" '{print $2}')"
sed -i "s/${orig_version}/${orig_version} ($(date +"%Y-%m-%d"))/g" zzz-default-settings
popd


# 添加额外软件包
mkdir package/community
pushd package/community

# SSRP
rm -rf package/helloworld
git clone --depth=1 https://github.com/fw876/helloworld.git package/helloworld

# Add OpenClash
#git clone --depth=1 https://github.com/vernesong/OpenClash

popd
