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
# 取消系统默认密码
sed -i 's@.*CYXluq4wUazHjmCDBCqXF*@#&@g' $ZZZ

# 修改主机名称为OpenWrt
sed -i "/uci commit system/i\uci set system.@system[0].hostname='OpenWrt'" $ZZZ
# 增加自己个性名称
sed -i "s/OpenWrt /Lrouter $(TZ=UTC-8 date "+%Y.%m.%d") @ OpenWrt /g" $ZZZ
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

echo '修改时区'
sed -i "s/'UTC'/'CST-8'\n   set system.@system[-1].zonename='Asia\/Shanghai'/g" package/base-files/files/bin/config_generate


# Clone community packages to package/community
mkdir package/community
pushd package/community


# Add OpenClash
git clone --depth=1 https://github.com/vernesong/OpenClash

popd

# 官方Docker
#svn co https://github.com/lisaac/luci-app-dockerman/trunk/applications/luci-app-dockerman package/luci-app-dockerman
#git clone --depth=1 https://github.com/lisaac/luci-lib-docker
#if [ -e feeds/packages/utils/docker-ce ];then
#	sed -i '/dockerd/d' package/luci-app-dockerman/Makefile
#	sed -i 's/+docker/+docker-ce/g' package/luci-app-dockerman/Makefile
#fi

# 解决冲突版docker
rm -rf package/lean/luci-app-docker
git clone --depth=1 https://github.com/KFERMercer/luci-app-dockerman
git clone --depth=1 https://github.com/lisaac/luci-lib-docker
