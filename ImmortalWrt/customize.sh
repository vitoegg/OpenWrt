#!/bin/bash
#=================================================
# Description: DIY script
# Lisence: MIT
# Author: P3TERX
# Blog: https://p3terx.com
#=================================================
# 修改默认IP
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate
# 取消系统默认密码
sed -i "/CYXluq4wUazHjmCDBCqXF/d" package/emortal/default-settings/files/zzz-default-settings

#修改主机名
sed -i 's/ImmortalWrt/OpenWrt/g' package/base-files/files/bin/config_generate

#修改默认显示
pushd package/emortal/default-settings/files
sed -i '/http/d' zzz-default-settings
sed -i '/openwrt_luci/d' zzz-default-settings
export orig_version=$(cat "zzz-default-settings" | grep DISTRIB_REVISION= | awk -F "'" '{print $2}')
export date_version=$(date +"%Y-%m-%d")
sed -i "s/${orig_version}/${orig_version} (${date_version})/g" zzz-default-settings
popd

# 使用OpenClash源码编译
pushd feeds/luci/applications
rm -rf luci-app-openclash
svn co https://github.com/vernesong/OpenClash/trunk/luci-app-openclash
popd

# 移除默认编译的插件
sed -i 's/luci-app-ddns//g;s/luci-app-upnp//g;s/luci-app-adbyby-plus//g;s/luci-app-vsftpd//g;s/luci-app-ssr-plus//g;s/luci-app-unblockmusic//g;s/luci-app-vlmcsd//g;s/luci-app-wol//g;s/luci-app-nlbwmon//g;s/luci-app-accesscontrol//g' include/target.mk
