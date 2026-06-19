#!/bin/bash -e

set -o pipefail

prepare_environment() {
    cat > "$BASH_ENV" <<'EOF'
CI_SEPARATOR='══════════════════════════════════════════════════'

ci_banner() {
  local color="$1"
  printf '\033[%sm%s\033[0m\n' "$color" "$CI_SEPARATOR"
}

ci_emit() {
  local banner_color="$1"
  local text_color="$2"
  local icon="$3"
  shift 3
  if [ -n "$banner_color" ]; then
    ci_banner "$banner_color"
  fi
  printf '\033[%sm%s %s\033[0m\n' "$text_color" "$icon" "$*"
}

ci_success_banner() { ci_banner '32'; }
ci_section() { ci_emit '32' '36' '●' "$*"; }
ci_highlight() { ci_emit '32' '36' '✓' "$*"; }
ci_success() { ci_emit '' '32' '✓' "$*"; }
ci_success_section() { ci_emit '32' '32' '✓' "$*"; }
ci_warn() { ci_emit '' '33' '⚠' "$*"; }
ci_warn_section() { ci_emit '33' '33' '⚠' "$*"; }
ci_error() { ci_emit '' '31' '✗' "$*"; }

cache_state() {
  case "$1" in
    true)
      printf 'exact-hit'
      ;;
    false)
      printf 'restore-hit'
      ;;
    *)
      printf 'miss'
      ;;
  esac
}
EOF

    source "$BASH_ENV"

    echo "::group::System snapshot"
    lscpu | grep -E 'name|Core|Thread'
    free -h
    df -Th
    uname -a
    echo "::endgroup::"

    echo "::group::Free disk space"
    sudo swapoff -a || true
    sudo rm -f /swapfile /mnt/swapfile
    sudo docker image prune -a -f || true
    sudo systemctl stop docker || true
    sudo snap set system refresh.retain=2 || true
    sudo apt-get -y purge firefox clang* gcc-12 gcc-14 ghc* google* llvm* mono* mongo* mysql* php* || true
    sudo apt-get -y autoremove --purge
    sudo apt-get clean
    sudo rm -rf /etc/mysql /etc/php /usr/lib/{jvm,llvm} /usr/libexec/docker /usr/local /usr/src/* \
      /var/lib/docker /var/lib/gems /var/lib/mysql /var/lib/snapd /etc/skel \
      /opt/{microsoft,az,hostedtoolcache,cni,mssql-tools,pipx} \
      /usr/share/{az*,dotnet,swift,miniconda,gradle*,java,kotlinc,ri,sbt} \
      /root/{.sbt,.local,.npm} /usr/libexec/gcc/x86_64-linux-gnu/14 \
      /usr/lib/x86_64-linux-gnu/{*clang*,*LLVM*} /home/linuxbrew
    sudo sed -i '/NVM_DIR/d;/skel/d' /root/{.bashrc,.profile} || true
    rm -rf ~/{.cargo,.dotnet,.rustup}
    df -Th
    echo "::endgroup::"

    echo "::group::Create swap"
    sudo fallocate -l 8G /mnt/swapfile || sudo dd if=/dev/zero of=/mnt/swapfile bs=1M count=8192
    sudo chmod 600 /mnt/swapfile
    sudo mkswap /mnt/swapfile
    sudo swapon /mnt/swapfile
    free -h | grep -i swap
    echo "::endgroup::"

    echo "::group::Install build dependencies"
    sudo -E apt-get -yqq update
    sudo -E apt-get -yqq install dos2unix python3-netifaces libfuse-dev ccache jq unzip wget \
      libelf-dev libdw-dev libbz2-dev liblzma-dev libzstd-dev
    sudo bash -c 'bash <(curl -fsSL https://build-scripts.immortalwrt.org/init_build_environment.sh)'
    sudo -E apt-get -yqq autoremove --purge
    sudo -E apt-get -yqq clean
    sudo -E systemctl daemon-reload
    sudo -E timedatectl set-timezone "Asia/Shanghai"
    echo "::endgroup::"

    echo "::group::Create workspace"
    mnt_size=$(df -BG /mnt | awk 'END {gsub(/G/, "", $4); print $4}')
    root_size=$(df -BG / | awk 'END {gsub(/G/, "", $4); print $4 - 2}')
    sudo truncate -s "${mnt_size}G" /mnt/mnt.img
    sudo truncate -s "${root_size}G" /root.img
    loop_mnt=$(sudo losetup -f --show /mnt/mnt.img)
    loop_root=$(sudo losetup -f --show /root.img)
    sudo pvcreate "$loop_mnt"
    sudo pvcreate "$loop_root"
    sudo vgcreate github "$loop_mnt" "$loop_root"
    sudo lvcreate -n runner -l 100%FREE github
    sudo mkfs.xfs /dev/github/runner
    sudo mkdir -p /builder
    sudo mount /dev/github/runner /builder
    sudo chown -R "$USER:$(id -gn)" /builder
    rm -rf "$GITHUB_WORKSPACE/wrt"
    ln -s /builder "$GITHUB_WORKSPACE/wrt"
    df -Th
    echo "::endgroup::"

    echo "::group::Init build context"
    source "$GITHUB_WORKSPACE/Build/Flow/lib.sh"
    load_profile "$BUILD_PROFILE"
    echo "BUILD_START_TIME=$(date +%s)" >> "$GITHUB_ENV"
    echo "TAG_TIME=$(TZ=Asia/Shanghai date +'%Y%m%d-%H%M')" >> "$GITHUB_ENV"
    echo "BUILD_DATE=$(TZ=Asia/Shanghai date +'%y.%m.%d')" >> "$GITHUB_ENV"
    echo "WRT_INFO=immortalwrt" >> "$GITHUB_ENV"
    echo "WRT_REPO=$WRT_REPO" >> "$GITHUB_ENV"
    echo "WRT_BRANCH=$WRT_BRANCH" >> "$GITHUB_ENV"
    echo "WRT_COMMIT=$WRT_COMMIT" >> "$GITHUB_ENV"
    echo "DEVICE_NAME=$DEVICE_NAME" >> "$GITHUB_ENV"
    find ./Build ./Custom ./Config -maxdepth 5 -type f -iregex '.*\(txt\|conf\|sh\)$' -exec dos2unix {} \;
    find ./Build -maxdepth 5 -type f -name '*.sh' -exec chmod +x {} \;
    echo "::endgroup::"

    ci_success_section "Runner ready"
}

select_build_mode() {
    if [ "$REQUESTED_BUILD_MODE" = 'FullBuilder' ]; then
      echo "BUILD_MODE=FullBuilder" >> "$GITHUB_ENV"
      ci_success_section "Build mode: FullBuilder"
      exit 0
    fi

    set +e
    bash "$GITHUB_WORKSPACE/Build/Action/RestoreImageBuilder.sh" \
      "$BUILD_PROFILE" "$GITHUB_WORKSPACE/wrt"
    restore_status=$?
    set -e

    case "$restore_status" in
      0)
        wrt_hash=$(jq -r '.wrt_hash' ./wrt/.imagebuilder-metadata.json)
        echo "BUILD_MODE=ImageBuilder" >> "$GITHUB_ENV"
        echo "WRT_HASH=$wrt_hash" >> "$GITHUB_ENV"
        ci_success_section "Build mode: ImageBuilder"
        ;;
      2)
        echo "BUILD_MODE=FullBuilder" >> "$GITHUB_ENV"
        ci_warn_section "ImageBuilder unavailable, falling back to FullBuilder"
        ;;
      *)
        ci_error "ImageBuilder restore failed with status $restore_status"
        exit "$restore_status"
        ;;
    esac
}

clone_source_and_feeds() {
    echo "::group::Clone source"
    if [ -n "$WRT_COMMIT" ]; then
      git init ./wrt
      cd ./wrt
      git remote add origin "$WRT_REPO"
      git fetch --depth=1 origin "$WRT_COMMIT"
      git checkout FETCH_HEAD
    else
      git clone --depth=1 --single-branch --branch "$WRT_BRANCH" "$WRT_REPO" ./wrt
      cd ./wrt
    fi

    wrt_hash=$(git log -1 --format='%H')
    echo "WRT_HASH=$wrt_hash" >> "$GITHUB_ENV"

    project_mirrors_file="./scripts/projectsmirrors.json"
    if [ -f "$project_mirrors_file" ]; then
      sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$project_mirrors_file"
    fi

    echo "::endgroup::"
    ci_highlight "Upstream commit: $wrt_hash"

    echo "::group::Update feeds"
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    echo "::endgroup::"
    ci_success_section "Feeds ready"
}

apply_customizations() {
    "$GITHUB_WORKSPACE/Build/Flow/ApplyPackages.sh" "$BUILD_PROFILE"
    "$GITHUB_WORKSPACE/Build/Flow/ApplyPrepare.sh" "$BUILD_PROFILE"
    ci_success_section "Sources prepared"

    cat "$GITHUB_WORKSPACE/Config/Common.txt" >> .config
    cat "$GITHUB_WORKSPACE/Config/$BUILD_PROFILE.txt" >> .config
    "$GITHUB_WORKSPACE/Build/Flow/ApplyPatches.sh" "$BUILD_PROFILE"
    "$GITHUB_WORKSPACE/Build/Flow/ApplySettings.sh" "$BUILD_PROFILE"

    echo "::group::make defconfig"
    make defconfig -j"$(nproc)"
    echo "::endgroup::"
    ci_success_section "$BUILD_PROFILE config applied"

    target_board=$(sed -n 's/^CONFIG_TARGET_BOARD="\([^"]*\)"/\1/p' .config | head -1)
    target_subtarget=$(sed -n 's/^CONFIG_TARGET_SUBTARGET="\([^"]*\)"/\1/p' .config | head -1)

    if [ -z "$target_board" ]; then
      target_board='x86'
    fi
    if [ -z "$target_subtarget" ]; then
      target_subtarget='64'
    fi

    # Extract toolchain-critical configs from .config for stable cache key
    # Only GCC/binutils/libc versions truly determine toolchain compatibility
    toolchain_sig=$(grep -E '^CONFIG_(GCC_VERSION|BINUTILS_VERSION|LIBC)=' .config | sort | sha256sum | cut -c1-12)
    if [ -z "$toolchain_sig" ] || [ "$toolchain_sig" = "e3b0c44298fc" ]; then
      # Fallback if no matching configs found (empty input hash)
      toolchain_sig="default"
    fi
    config_sig=$(sha256sum .config | cut -c1-16)
    cache_run_suffix="${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"

    profile_lower=$(echo "$BUILD_PROFILE" | tr '[:upper:]' '[:lower:]')
    dl_cache_prefix="wrt-dl-${WRT_BRANCH}"
    toolchain_cache_prefix="toolchain-${WRT_BRANCH}-${target_board}-${target_subtarget}-${toolchain_sig}"
    toolchain_cache_clean_prefix="toolchain-${WRT_BRANCH}-${target_board}-${target_subtarget}-"
    ccache_cache_prefix="ccache-openwrt-${profile_lower}-${WRT_BRANCH#openwrt-}-${target_board}-${target_subtarget}-${config_sig}"
    ccache_cache_clean_prefix="ccache-openwrt-${profile_lower}-${WRT_BRANCH#openwrt-}-${target_board}-${target_subtarget}-"

    echo "TARGET_BOARD=$target_board" >> "$GITHUB_ENV"
    echo "TARGET_SUBTARGET=$target_subtarget" >> "$GITHUB_ENV"
    echo "TOOLCHAIN_SIG=$toolchain_sig" >> "$GITHUB_ENV"
    echo "CONFIG_SIG=$config_sig" >> "$GITHUB_ENV"
    echo "DL_CACHE_PREFIX=$dl_cache_prefix" >> "$GITHUB_ENV"
    echo "DL_CACHE_KEY=${dl_cache_prefix}-${cache_run_suffix}" >> "$GITHUB_ENV"
    echo "TOOLCHAIN_CACHE_PREFIX=$toolchain_cache_prefix" >> "$GITHUB_ENV"
    echo "TOOLCHAIN_CACHE_KEY=${toolchain_cache_prefix}-${cache_run_suffix}" >> "$GITHUB_ENV"
    echo "TOOLCHAIN_CACHE_CLEAN_PREFIX=$toolchain_cache_clean_prefix" >> "$GITHUB_ENV"
    echo "CCACHE_CACHE_PREFIX=$ccache_cache_prefix" >> "$GITHUB_ENV"
    echo "CCACHE_CACHE_KEY=${ccache_cache_prefix}-${cache_run_suffix}" >> "$GITHUB_ENV"
    echo "CCACHE_CACHE_CLEAN_PREFIX=$ccache_cache_clean_prefix" >> "$GITHUB_ENV"

    ci_success_banner
    ci_success "Target detected: ${target_board}/${target_subtarget}"
    ci_success "Toolchain signature: ${toolchain_sig}"
    ci_success "Config signature: ${config_sig}"
}

download_sources() {
    report_cache() {
      local label="$1" state="$2"
      if [ "$state" = 'miss' ]; then
        ci_warn "${label} cache: ${state}"
      else
        ci_success "${label} cache: ${state}"
      fi
    }

    dl_state=$(cache_state "$DOWNLOAD_CACHE_HIT")
    toolchain_state=$(cache_state "$TOOLCHAIN_CACHE_HIT")
    ccache_state=$(cache_state "$CCACHE_CACHE_HIT")

    report_cache 'Download' "$dl_state"
    report_cache 'Toolchain' "$toolchain_state"
    report_cache 'Ccache' "$ccache_state"

    echo "::group::Restore cache timestamps"
    if [ -d "./staging_dir" ]; then
      find ./staging_dir -type d -name stamp -not -path '*target*' | while read -r dir; do
        find "$dir" -type f -exec touch {} +
      done
      mkdir -p ./tmp
      echo '1' > ./tmp/.build
    fi
    echo "::endgroup::"

    list_suspicious_files() {
      find dl -maxdepth 1 -type f -size -1024c | sort
    }

    count_suspicious_files() {
      list_suspicious_files | wc -l | tr -d ' '
    }

    download_jobs=$(( $(nproc) * 2 ))
    if [ "$download_jobs" -gt 16 ]; then
      download_jobs=16
    fi

    ci_section "Downloading source archives"
    echo "::group::Download source archives"
    make download -j"$download_jobs"
    echo "::endgroup::"

    bad_files=$(count_suspicious_files)
    if [ "$bad_files" -gt 0 ]; then
      ci_warn "Found ${bad_files} suspicious root-level download files smaller than 1 KB"
      while IFS= read -r file; do
        [ -n "$file" ] || continue
        ls -l "$file"
        rm -f "$file"
      done < <(list_suspicious_files)

      echo "::group::Retry source archives download"
      make download -j"$download_jobs"
      echo "::endgroup::"

      remaining_bad_files=$(count_suspicious_files)
      if [ "$remaining_bad_files" -gt 0 ]; then
        while IFS= read -r file; do
          [ -n "$file" ] || continue
          ls -l "$file"
        done < <(list_suspicious_files)
        ci_error "Download retry still found ${remaining_bad_files} suspicious root-level files smaller than 1 KB"
        exit 1
      fi

      ci_warn "Suspicious files removed and successfully re-downloaded"
    else
      ci_success "All downloaded source archives look valid"
    fi
}

compile_fullbuilder() {
    ci_section "Starting parallel build with $(nproc) jobs"
    compile_failed=false
    echo "::group::Parallel build output"
    if ! make -j"$(nproc)"; then
      compile_failed=true
    fi
    echo "::endgroup::"

    if [ "$compile_failed" = true ]; then
      ci_warn_section "Parallel build failed, retrying with make -j1 V=s"
      echo "::group::Verbose retry"
      make -j1 V=s
      echo "::endgroup::"

      ci_warn_section "Build succeeded after verbose retry"
    else
      ci_success_section "Build succeeded on the first pass"
    fi

    echo "BUILD_OK=true" >> "$GITHUB_ENV"
}

assemble_imagebuilder() {
    rm -rf files bin

    "$GITHUB_WORKSPACE/Build/Flow/ApplyPrepare.sh" "$BUILD_PROFILE"
    rm -f files/etc/banner
    "$GITHUB_WORKSPACE/Build/Flow/ApplySettings.sh" "$BUILD_PROFILE"

    common_config="$GITHUB_WORKSPACE/Config/Common.txt"
    profile_config="$GITHUB_WORKSPACE/Config/$BUILD_PROFILE.txt"
    if [ ! -f "$common_config" ] || [ ! -f "$profile_config" ]; then
      ci_error "ImageBuilder package config not found"
      exit 1
    fi
    package_removes=$(sed -n 's/^# CONFIG_PACKAGE_\([^[:space:]]\{1,\}\) is not set$/-\1/p' \
      "$common_config" "$profile_config" | sort -u | tr '\n' ' ')
    packages="${package_removes}$(tr '\n' ' ' < .imagebuilder-packages)"
    rootfs_partsize=$(sed -n 's/^CONFIG_TARGET_ROOTFS_PARTSIZE=//p' .config | head -1)
    rootfs_partsize=${rootfs_partsize:-2048}

    ci_section "Building firmware with ImageBuilder"
    make image \
      PROFILE=generic \
      PACKAGES="$packages" \
      FILES=files \
      ROOTFS_PARTSIZE="$rootfs_partsize"

    image_manifest=$(find ./bin -type f -name '*.manifest' -print -quit)
    if [ -z "$image_manifest" ]; then
      ci_error "ImageBuilder manifest not found"
      exit 1
    fi

    awk 'NF >= 3 && $2 == "-" {print $1}' "$image_manifest" | sort -u > /tmp/imagebuilder-packages
    if ! diff -u .imagebuilder-packages /tmp/imagebuilder-packages; then
      ci_error "ImageBuilder package manifest changed"
      exit 1
    fi

    echo "BUILD_OK=true" >> "$GITHUB_ENV"
    ci_success_section "ImageBuilder firmware ready"
}

publish_imagebuilder() {
    bash "$GITHUB_WORKSPACE/Build/Action/PublishImageBuilder.sh" \
      "$BUILD_PROFILE" "$GITHUB_WORKSPACE/wrt"
}

purge_stale_caches() {
    purge_latest_cache_by_prefix() {
      local label="$1"
      local list_prefix="$2"
      local save_outcome="$3"
      local cache_entries
      local keep_key
      local stale_ids
      local cache_count
      local stale_count

      if [ "$save_outcome" != 'success' ]; then
        ci_warn "${label} cache save skipped or failed, keeping previous cache"
        return 0
      fi

      if [ -z "$list_prefix" ]; then
        ci_warn "${label} cache prefix is empty, skipping purge"
        return 0
      fi

      cache_entries=$(gh cache list --limit 1000 --repo "$GITHUB_REPOSITORY" --key "$list_prefix" --json id,key,createdAt | \
        jq -c --arg list_prefix "$list_prefix" '
          map(select(.key | startswith($list_prefix))) |
          sort_by(.createdAt) |
          reverse
        ')

      cache_count=$(printf '%s\n' "$cache_entries" | jq 'length')
      if [ "$cache_count" -eq 0 ]; then
        ci_warn "No ${label} caches found for prefix ${list_prefix}"
        return 0
      fi

      keep_key=$(printf '%s\n' "$cache_entries" | jq -r '.[0].key')
      stale_ids=$(printf '%s\n' "$cache_entries" | jq -r '.[1:][]?.id')
      stale_count=$(printf '%s\n' "$cache_entries" | jq '.[1:] | length')

      ci_success "${label} cache retained: ${keep_key}"

      if [ "$stale_count" -eq 0 ]; then
        ci_success "No stale ${label} caches to purge"
        return 0
      fi

      while IFS= read -r cache_id; do
        [ -n "$cache_id" ] || continue
        gh cache delete "$cache_id" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1 || true
      done <<< "$stale_ids"

      ci_success "Old ${label} caches purged: ${stale_count}"
    }

    purge_latest_cache_by_prefix 'Download' "${DL_CACHE_PREFIX}-" "$DOWNLOAD_CACHE_SAVE_OUTCOME"
    purge_latest_cache_by_prefix 'Toolchain' "${TOOLCHAIN_CACHE_CLEAN_PREFIX}" "$TOOLCHAIN_CACHE_SAVE_OUTCOME"
    purge_latest_cache_by_prefix 'Ccache' "${CCACHE_CACHE_CLEAN_PREFIX}" "$CCACHE_CACHE_SAVE_OUTCOME"
}

deliver_firmware() {
    echo "::group::Collect build metadata"
    build_end_time=$(date +%s)
    build_time=$((build_end_time - BUILD_START_TIME))
    build_hours=$((build_time / 3600))
    build_minutes=$(((build_time % 3600) / 60))
    if [ "$build_hours" -gt 0 ]; then
      build_duration="${build_hours}h${build_minutes}min"
    else
      build_duration="${build_minutes}min"
    fi
    echo "BUILD_DURATION=$build_duration" >> "$GITHUB_ENV"

    kernel_ver=$(find ./bin/targets -type f -name '*.manifest' -exec grep -oP '^kernel - \K[\d\.]+' {} \; | head -1)
    if [ -z "$kernel_ver" ]; then
      kernel_ver=$(grep -m1 '^KERNEL_PATCHVER:=' include/kernel-version.mk | sed 's/^KERNEL_PATCHVER:=//' | tr -d ' ')
    fi
    echo "KERNEL_PATCHVER=$kernel_ver" >> "$GITHUB_ENV"

    luci_branch=$WRT_BRANCH
    if [ -f .imagebuilder-metadata.json ]; then
      imagebuilder_branch=$(jq -r '.wrt_branch // empty' .imagebuilder-metadata.json)
      [ -z "$imagebuilder_branch" ] || luci_branch=$imagebuilder_branch
    fi
    luci_ver=${luci_branch#openwrt-}
    if [ -z "$luci_ver" ]; then
      luci_ver='unknown'
    fi
    echo "LUCI_VERSION=$luci_ver" >> "$GITHUB_ENV"
    echo "::endgroup::"

    echo "::group::Package firmware"
    firmware_path=$(find ./bin/targets/x86 -type f -name '*-squashfs-combined-efi.img.gz' | head -n1)
    profile_lower=$(echo "$BUILD_PROFILE" | tr '[:upper:]' '[:lower:]')
    firmware_name="openwrt-${profile_lower}-${TAG_TIME}-x86-64-efi.img.gz"

    mkdir -p ./upload
    cp -f ./.config "./upload/${profile_lower}-config-${TAG_TIME}.txt"
    cp -f "$firmware_path" "./upload/$firmware_name"
    echo "FIRMWARE_NAME=$firmware_name" >> "$GITHUB_ENV"
    echo "::endgroup::"

    ci_success_section "Firmware ready: $firmware_name ($build_duration)"

    echo "::group::Upload firmware"
    rclone copy "${GITHUB_WORKSPACE}/wrt/upload/" remote:/OpenWrt/ \
      --include "*.img.gz" \
      --transfers=1 \
      --stats-one-line \
      --stats=20s
    echo "::endgroup::"
    ci_success "Firmware uploaded to remote:/OpenWrt/"

    echo "::group::Send notification"
    curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto" \
      -d chat_id=${TELEGRAM_CHAT_ID} \
      -d photo='https://mirror.1991991.xyz/Picture/openwrt.webp' \
      --data-urlencode "caption=#OpenWRT #${DEVICE_NAME}

    *🎉 Ready to roll! Dive in! 🎉*

    - 🌐 Kernel: ${kernel_ver}

    - 📦 LuCI: ${luci_ver}

    - ⌛ Build Duration: ${build_duration}

    - 🔗 Firmware: [Click to View](${FIRMWARE_DOWNLOAD_URL})" \
      -d parse_mode=Markdown >/dev/null 2>&1
    echo "::endgroup::"
    ci_success "Notification sent"
}

usage() {
    printf "Usage: %s <%s>\n" "$0" \
        "prepare-environment|select-build-mode|clone-source-and-feeds|apply-customizations|download-sources|compile-fullbuilder|assemble-imagebuilder|publish-imagebuilder|purge-stale-caches|deliver-firmware" >&2
}

main() {
    case "${1:-}" in
        prepare-environment)
            prepare_environment
            ;;
        select-build-mode)
            select_build_mode
            ;;
        clone-source-and-feeds)
            clone_source_and_feeds
            ;;
        apply-customizations)
            apply_customizations
            ;;
        download-sources)
            download_sources
            ;;
        compile-fullbuilder)
            compile_fullbuilder
            ;;
        assemble-imagebuilder)
            assemble_imagebuilder
            ;;
        publish-imagebuilder)
            publish_imagebuilder
            ;;
        purge-stale-caches)
            purge_stale_caches
            ;;
        deliver-firmware)
            deliver_firmware
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
