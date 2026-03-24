#!/bin/bash -e

### Add new packages or patches below
### For example, download alist from a third-party repository to package/new/alist
### Then, add CONFIG_PACKAGE_luci-app-alist=y to the end of openwrt/23-config-common-custom

# Logging function
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg"
}

# REMOVE_PKG: Remove matching package directories from package/new/
# Usage: REMOVE_PKG <name> [name2] [name3] ...
REMOVE_PKG() {
    for name in "$@"; do
        log "Searching: $name"
        local found
        found=$(find package/new/ -maxdepth 3 -type d -iname "*$name*" 2>/dev/null)
        if [ -n "$found" ]; then
            while read -r dir; do
                rm -rf "$dir"
                log "Removed: $dir"
            done <<< "$found"
        else
            log "Not found: $name"
        fi
    done
}

# CLONE_PKG: Clone a GitHub repo into a target path under package/new/extd/
# Usage: CLONE_PKG <repo> <branch> [dest_name]
#   dest_name: optional directory name (defaults to repo basename)
CLONE_PKG() {
    local repo=$1
    local branch=$2
    local dest_name=${3:-${repo#*/}}
    local dest="package/new/extd/$dest_name"
    log "Cloning $repo ($branch) -> $dest"
    git clone --depth=1 --single-branch -b "$branch" "https://github.com/${repo}.git" "$dest"
}

# ===== Package Installation =====

# Argon - replace built-in with customized theme
REMOVE_PKG "luci-theme-argon"
CLONE_PKG "vitoegg/Argon" "main" "luci-theme-argon"

# Mio - add personalized ssserver
CLONE_PKG "vitoegg/Mio" "master" "Mio"

# Apps not needed in the Cloud version
REMOVE_PKG \
    "smartdns" \
    "luci-app-dae"

# Modify Hostname
log "Modifying hostname to HomeCloud"
sed -i 's#OpenWrt#HomeCloud#g' package/base-files/files/bin/config_generate

# Set CPU Mode
log "Setting CPU mode to PERFORMANCE"
KERNEL_CONFIG=$(find target/linux/x86 -maxdepth 1 -name 'config-*' -type f | head -1)
KERNEL_CONFIG_64=$(find target/linux/x86/64 -maxdepth 1 -name 'config-*' -type f 2>/dev/null | head -1)

if [ -n "$KERNEL_CONFIG" ]; then
    log "Found kernel config: $KERNEL_CONFIG"
    sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND is not set/g' "$KERNEL_CONFIG"
    sed -i 's/CONFIG_CPU_FREQ_GOV_ONDEMAND=y/# CONFIG_CPU_FREQ_GOV_ONDEMAND is not set/g' "$KERNEL_CONFIG"
    sed -i 's/# CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE is not set/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' "$KERNEL_CONFIG"
fi

if [ -n "$KERNEL_CONFIG_64" ]; then
    log "Found kernel config (64-bit): $KERNEL_CONFIG_64"
    sed -i 's/CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y/g' "$KERNEL_CONFIG_64"
    sed -i 's/CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y/CONFIG_CPU_FREQ_GOV_PERFORMANCE=y/g' "$KERNEL_CONFIG_64"
fi

# Delete LED Menu
log "Removing LED menu from LuCI"
awk '
BEGIN { skip=0; brace_count=0; }
/[[:space:]]*"admin\/system\/leds": {/ { 
  skip=1; 
  brace_count=1; 
  next; 
}
{
  if(skip==1) {
    if($0 ~ /{/) brace_count++;
    if($0 ~ /}/) brace_count--;
    if(brace_count==0) {
      if($0 ~ /},/) {
        skip=0;
        next;
      } else if($0 ~ /}/) {
        skip=0;
        next;
      }
    }
  } else {
    print;
  }
}
' feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json > /tmp/temp.json && mv /tmp/temp.json feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json

# Hide empty DHCP/DHCPv6 Leases section on status overview page
log "Patching DHCP lease display to auto-hide when empty"
DHCP_FILE="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/40_dhcp.js"
awk '
/return E\(\[/ { hold=1; buf=$0; next }
hold {
    buf=buf ORS $0
    if (/\]\);/) {
        if (buf ~ /Active DHCPv6 Leases/) {
            print "\t\tconst result = [];"
            print "\t\tif (leases.length > 0) {"
            print "\t\t\tresult.push(E('\''h3'\'', _('\''Active DHCPv4 Leases'\'')));"
            print "\t\t\tresult.push(table);"
            print "\t\t}"
            print "\t\tif (leases6.length > 0) {"
            print "\t\t\tresult.push(E('\''h3'\'', _('\''Active DHCPv6 Leases'\'')));"
            print "\t\t\tresult.push(table6);"
            print "\t\t}"
            print "\t\treturn E(result);"
        } else {
            print buf
        }
        hold=0; buf=""
    }
    next
}
{ print }
' "$DHCP_FILE" > /tmp/40_dhcp_patched.js && mv /tmp/40_dhcp_patched.js "$DHCP_FILE"

# Setting up etc config
log "Setting up etc config"
ZZZ="package/new/default-settings/default/zzz-default-settings"
cat >> $ZZZ <<-EOF
# Set customizedpassword
sed -i 's|root:::0:99999:7:::|root:$ROOT_PASSWORD_HASH:20211:0:99999:7:::|g' /etc/shadow
# Enable auto mount
uci set fstab.@global[0].anon_mount='1'
uci commit fstab
EOF
sed -i '/exit 0/d' $ZZZ && echo "exit 0" >> $ZZZ

# Move configuration files
log "Downloading pre-configuration files"
REPO_TEMP_DIR=$(mktemp -d)
curl -s -S -f -L -u "$REPO_USERNAME:$REPO_TOKEN" "$REPO_URL" -o "$REPO_TEMP_DIR/repo.zip" 2>/dev/null
unzip -q "$REPO_TEMP_DIR/repo.zip" -d "$REPO_TEMP_DIR/"
log "Setting up pre-configuration files"
# Remove existing files/etc directory and recreate it
rm -rf files/etc && mkdir -p files/etc
mv "$REPO_TEMP_DIR"/*/Cloud/files/etc/* files/etc/
rm -rf "$REPO_TEMP_DIR"

# Add docker restart task to crontabs
log "Adding docker restart task to crontabs"
mkdir -p files/etc/crontabs
echo "15 5 * * * docker restart tunnel" >> files/etc/crontabs/root

# Download ddns script
log "Downloading ddns script"
mkdir -p files/usr/share/task
wget -qO- $DDNS_SH_URL > files/usr/share/task/ddns.sh
chmod +x files/usr/share/task/ddns.sh
log "Adding ddns script to crontabs"
echo "*/30 * * * * /usr/share/task/ddns.sh > /dev/null 2>&1" >> files/etc/crontabs/root

log "Script completed successfully"
