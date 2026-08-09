#!/bin/bash -e

set -eo pipefail

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
EOF

    source "$BASH_ENV"

    cpu_model=$(lscpu | sed -n 's/^Model name:[[:space:]]*//p')
    memory_total=$(free -h | awk '/^Mem:/ {print $2; exit}')
    ci_banner '36'
    printf '\033[36m● Runner\033[0m\n'
    printf '\033[36m  CPU  %s\033[0m\n' "$cpu_model"
    printf '\033[36m  RES  %s vCPU | %s RAM\033[0m\n' "$(nproc)" "$memory_total"
    ci_banner '36'

    case "${REQUESTED_BUILD_MODE:-}" in
      ImageBuilder|CacheBuilder|RefreshBuilder|PureBuilder)
        ;;
      *)
        ci_error "Unsupported build mode: ${REQUESTED_BUILD_MODE:-empty}"
        exit 1
        ;;
    esac

    source "$GITHUB_WORKSPACE/Build/lib.sh"
    load_profile "$BUILD_PROFILE"
    echo "BUILD_START_TIME=$(date +%s)" >> "$GITHUB_ENV"
    echo "TAG_TIME=$(TZ=Asia/Shanghai date +'%Y%m%d-%H%M')" >> "$GITHUB_ENV"
    echo "BUILD_DATE=$(TZ=Asia/Shanghai date +'%y.%m.%d')" >> "$GITHUB_ENV"
    echo "WRT_INFO=immortalwrt" >> "$GITHUB_ENV"
    echo "WRT_REPO=$WRT_REPO" >> "$GITHUB_ENV"
    echo "WRT_BRANCH=$WRT_BRANCH" >> "$GITHUB_ENV"
    echo "WRT_COMMIT=$WRT_COMMIT" >> "$GITHUB_ENV"
    echo "DEVICE_NAME=$DEVICE_NAME" >> "$GITHUB_ENV"
    echo "BUILD_PROFILE=$BUILD_PROFILE" >> "$GITHUB_ENV"
    rm -rf "$GITHUB_WORKSPACE/wrt" "$GITHUB_WORKSPACE/ib"
    mkdir -p "$GITHUB_WORKSPACE/wrt" "$GITHUB_WORKSPACE/ib"

    for command in curl jq make tar unzip wget zstd; do
      if ! command -v "$command" >/dev/null 2>&1; then
        ci_error "Required command not found: $command"
        exit 1
      fi
    done

    oras_version='1.3.3'
    curl -fSsL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 120 \
      "https://github.com/oras-project/oras/releases/download/v${oras_version}/oras_${oras_version}_linux_amd64.tar.gz" \
      | sudo tar -xz -C /usr/bin oras

    force_apps=false
    clean_build=false
    case "$REQUESTED_BUILD_MODE" in
      CacheBuilder)
        build_mode='CacheBuilder'
        ;;
      PureBuilder)
        build_mode='CacheBuilder'
        clean_build=true
        ;;
      ImageBuilder|RefreshBuilder)
        if [ "$REQUESTED_BUILD_MODE" = 'RefreshBuilder' ]; then
          force_apps=true
        fi

        set +e
        bash "$GITHUB_WORKSPACE/Build/Action/ImageBuilder.sh" restore \
          "$BUILD_PROFILE" "$GITHUB_WORKSPACE/ib"
        restore_status=$?
        set -e

        case "$restore_status" in
          0)
            build_mode='ImageBuilder'
            ;;
          2)
            build_mode='CacheBuilder'
            ci_warn "ImageBuilder unavailable, falling back to CacheBuilder"
            ;;
          *)
            ci_error "ImageBuilder restore failed with status $restore_status"
            exit "$restore_status"
            ;;
        esac
        ;;
    esac

    echo "BUILD_MODE=$build_mode" >> "$GITHUB_ENV"
    echo "FORCE_APPS=$force_apps" >> "$GITHUB_ENV"
    echo "CLEAN_BUILD=$clean_build" >> "$GITHUB_ENV"

    if [ "$build_mode" = 'ImageBuilder' ]; then
      echo "BUILD_DIR=ib" >> "$GITHUB_ENV"
      wrt_hash=$(jq -r '.wrt_hash' "$GITHUB_WORKSPACE/ib/.imagebuilder-metadata.json")
      echo "WRT_HASH=$wrt_hash" >> "$GITHUB_ENV"
    else
      echo "BUILD_DIR=wrt" >> "$GITHUB_ENV"

      sudo swapoff -a || true
      sudo rm -f /swapfile /mnt/swapfile
      sudo fallocate -l 8G /mnt/swapfile || \
        sudo dd if=/dev/zero of=/mnt/swapfile bs=1M count=8192 status=none
      sudo chmod 600 /mnt/swapfile
      sudo mkswap /mnt/swapfile >/dev/null
      sudo swapon /mnt/swapfile

      apt_options=(
        -o Acquire::Retries=3
        -o Acquire::http::Timeout=30
        -o Acquire::https::Timeout=30
      )
      sudo -E apt-get "${apt_options[@]}" -yqq update >/dev/null
      sudo -E env NEEDRESTART_SUSPEND=1 \
        apt-get "${apt_options[@]}" -yqq install --no-install-recommends --no-upgrade \
          build-essential ccache gawk gettext libncurses-dev libssl-dev python3 rsync swig unzip \
          zlib1g-dev libelf-dev libdw-dev libbz2-dev liblzma-dev libzstd-dev >/dev/null
    fi

    swap_total=$(free -h | awk '/^Swap:/ {print $2; exit}')
    disk_available=$(df -h --output=avail / | awk 'NR == 2 {print $1}')
    ci_success "Runner ready: $build_mode | $swap_total Swap | $disk_available free"
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
    bash "$GITHUB_WORKSPACE/Build/Flow/ApplyPackages.sh" "$BUILD_PROFILE"
    bash "$GITHUB_WORKSPACE/Build/Flow/ApplyPrepare.sh" "$BUILD_PROFILE"
    ci_success_section "Sources prepared"

    cat "$GITHUB_WORKSPACE/Config/Common.txt" >> .config
    cat "$GITHUB_WORKSPACE/Config/$BUILD_PROFILE.txt" >> .config
    bash "$GITHUB_WORKSPACE/Build/Flow/ApplyPatches.sh" "$BUILD_PROFILE"
    bash "$GITHUB_WORKSPACE/Build/Flow/ApplySettings.sh" "$BUILD_PROFILE"

    echo "::group::make defconfig"
    make defconfig -j"$(nproc)"
    echo "::endgroup::"

    ci_success_section "$BUILD_PROFILE config applied"
}

download_sources() {
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

compile_cachebuilder() {
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

    bash "$GITHUB_WORKSPACE/Build/Flow/ApplyPrepare.sh" "$BUILD_PROFILE"
    rm -f files/etc/banner
    bash "$GITHUB_WORKSPACE/Build/Flow/ApplySettings.sh" "$BUILD_PROFILE"

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

    # APK ImageBuilder expects this file; missing it floods logs with warnings
    touch repositories

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

restore_cache() {
    bash "$GITHUB_WORKSPACE/Build/Action/BuildCache.sh" restore \
      "$BUILD_PROFILE" "$GITHUB_WORKSPACE/wrt"
}

publish_cache() {
    bash "$GITHUB_WORKSPACE/Build/Action/BuildCache.sh" publish \
      "$BUILD_PROFILE" "$GITHUB_WORKSPACE/wrt"
}

publish_imagebuilder() {
    bash "$GITHUB_WORKSPACE/Build/Action/ImageBuilder.sh" publish \
      "$BUILD_PROFILE" "$GITHUB_WORKSPACE/wrt"
}

publish_sdk() {
    bash "$GITHUB_WORKSPACE/Build/Action/BuildApps.sh" publish \
      "$BUILD_PROFILE" "$GITHUB_WORKSPACE/wrt"
}

check_apps() {
    bash "$GITHUB_WORKSPACE/Build/Action/BuildApps.sh" check \
      "$BUILD_PROFILE" "$GITHUB_WORKSPACE/ib"
}

build_apps() {
    bash "$GITHUB_WORKSPACE/Build/Action/BuildApps.sh" build \
      "$BUILD_PROFILE" "$GITHUB_WORKSPACE/wrt" "$GITHUB_WORKSPACE/ib"
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
    rclone copy "${GITHUB_WORKSPACE}/${BUILD_DIR:-wrt}/upload/" remote:/OpenWrt/ \
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
        "prepare-environment|clone-source-and-feeds|apply-customizations|restore-cache|download-sources|compile-cachebuilder|publish-cache|assemble-imagebuilder|publish-imagebuilder|publish-sdk|check-apps|build-apps|deliver-firmware" >&2
}

main() {
    case "${1:-}" in
        prepare-environment)
            prepare_environment
            ;;
        clone-source-and-feeds)
            clone_source_and_feeds
            ;;
        apply-customizations)
            apply_customizations
            ;;
        restore-cache)
            restore_cache
            ;;
        publish-cache)
            publish_cache
            ;;
        download-sources)
            download_sources
            ;;
        compile-cachebuilder)
            compile_cachebuilder
            ;;
        assemble-imagebuilder)
            assemble_imagebuilder
            ;;
        publish-imagebuilder)
            publish_imagebuilder
            ;;
        publish-sdk)
            publish_sdk
            ;;
        check-apps)
            check_apps
            ;;
        build-apps)
            build_apps
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
