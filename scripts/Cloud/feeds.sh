#!/bin/bash
#=================================================
# Description: DIY script
# Lisence: MIT
# Author: P3TERX
# Blog: https://p3terx.com
#=================================================

# Enable Luci 18.06
#sed -i '/^#src-git luci https:\/\/github.com\/coolsnowwolf\/luci$/s/^#//' feeds.conf.default
# Disable Luci 24.10
#sed -i '/^src-git luci https:\/\/github.com\/coolsnowwolf\/luci\.git;openwrt-24\.10$/s/^/#/' feeds.conf.default

# Update and Install
./scripts/feeds update -a && ./scripts/feeds install -a
