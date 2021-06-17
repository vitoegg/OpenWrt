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
#

# 修改默认IP
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# 添加libcap-bin依赖
rm -rf feeds/packages/libs/libcap
svn co https://github.com/vitoegg/packages/trunk/libs/libcap feeds/packages/libs/libcap


# Clone community packages to package/community
#mkdir package/community
#pushd package/community


# Add OpenClash
#git clone --depth=1 https://github.com/vernesong/OpenClash

# 原版Dockerman
#rm -rf ../lean/luci-app-docker
#git clone --depth=1 https://github.com/lisaac/luci-app-dockerman
#git clone --depth=1 https://github.com/lisaac/luci-lib-docker

# Add luci-theme-argon
#git clone --depth=1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon
#git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config
#rm -rf ../lean/luci-theme-argon

#popd
