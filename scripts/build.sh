#!/bin/bash

# Entry point of the firmware workflow, one subcommand per workflow step

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/core.sh"

STEPS=(
    prepare-environment clone-source-and-feeds apply-customizations restore-cache
    download-sources compile-cachebuilder publish-imagebuilder publish-sdk publish-cache
    check-apps build-apps assemble-imagebuilder deliver-firmware
)

ARTIFACTS_DIR="$REPO_ROOT/scripts/artifacts"
CUSTOMIZE_DIR="$REPO_ROOT/scripts/customize"
WRT_DIR="$REPO_ROOT/wrt"
IB_DIR="$REPO_ROOT/ib"
ORAS_VERSION="1.3.3"

set_env() {
    echo "$1=$2" >> "$GITHUB_ENV"
}

prepare_environment() {
    local name
    local build_mode
    local force_apps=false
    local clean_build=false
    local restore_status
    local apt_options

    section "Runner"
    log "CPU: $(lscpu | sed -n 's/^Model name:[[:space:]]*//p')"
    log "Resources: $(nproc) vCPU, $(free -h | awk '/^Mem:/ {print $2; exit}') RAM"

    case "${REQUESTED_BUILD_MODE:-}" in
        ImageBuilder|CacheBuilder|RefreshBuilder|PureBuilder)
            ;;
        *)
            die "Unsupported build mode: ${REQUESTED_BUILD_MODE:-empty}"
            ;;
    esac

    load_profile "$BUILD_PROFILE"
    set_env BUILD_START_TIME "$(date +%s)"
    set_env TAG_TIME "$(TZ=Asia/Shanghai date +'%Y%m%d-%H%M')"
    set_env BUILD_DATE "$(TZ=Asia/Shanghai date +'%y.%m.%d')"
    set_env WRT_REPO "$WRT_REPO"
    set_env WRT_BRANCH "$WRT_BRANCH"
    set_env WRT_COMMIT "$WRT_COMMIT"
    set_env DEVICE_NAME "$DEVICE_NAME"
    rm -rf "$WRT_DIR" "$IB_DIR"
    mkdir -p "$WRT_DIR" "$IB_DIR"

    for name in curl jq make tar unzip wget zstd; do
        require_command "$name"
    done

    curl -fSsL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 120 \
        "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz" |
        sudo tar -xz -C /usr/bin oras

    case "$REQUESTED_BUILD_MODE" in
        CacheBuilder)
            build_mode="CacheBuilder"
            ;;
        PureBuilder)
            build_mode="CacheBuilder"
            clean_build=true
            ;;
        ImageBuilder|RefreshBuilder)
            if [ "$REQUESTED_BUILD_MODE" = "RefreshBuilder" ]; then
                force_apps=true
            fi

            set +e
            bash "$ARTIFACTS_DIR/imagebuilder.sh" restore "$BUILD_PROFILE" "$IB_DIR"
            restore_status=$?
            set -e

            case "$restore_status" in
                0)
                    build_mode="ImageBuilder"
                    ;;
                2)
                    build_mode="CacheBuilder"
                    log "Falling back to CacheBuilder"
                    ;;
                *)
                    die "ImageBuilder restore failed with status $restore_status"
                    ;;
            esac
            ;;
    esac

    set_env BUILD_MODE "$build_mode"
    set_env FORCE_APPS "$force_apps"
    set_env CLEAN_BUILD "$clean_build"

    if [ "$build_mode" = "ImageBuilder" ]; then
        set_env BUILD_DIR ib
        set_env WRT_HASH "$(jq -r '.wrt_hash' "$IB_DIR/.imagebuilder-metadata.json")"
    else
        set_env BUILD_DIR wrt

        sudo swapoff -a || true
        sudo rm -f /swapfile /mnt/swapfile
        sudo fallocate -l 8G /mnt/swapfile ||
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

    milestone "Runner ready: $build_mode, $(free -h | awk '/^Swap:/ {print $2; exit}') swap," \
        "$(df -h --output=avail / | awk 'NR == 2 {print $1}') free"
}

clone_source_and_feeds() {
    local wrt_hash
    local mirrors_file="scripts/projectsmirrors.json"

    group "Clone source"
    if [ -n "$WRT_COMMIT" ]; then
        git init "$WRT_DIR"
        cd "$WRT_DIR"
        git remote add origin "$WRT_REPO"
        git fetch --depth=1 origin "$WRT_COMMIT"
        git checkout FETCH_HEAD
        cp "$REPO_ROOT/profiles/feeds.conf" ./feeds.conf
        cat ./feeds.conf
    else
        git clone --depth=1 --single-branch --branch "$WRT_BRANCH" "$WRT_REPO" "$WRT_DIR"
        cd "$WRT_DIR"
    fi

    wrt_hash=$(git log -1 --format='%H')
    set_env WRT_HASH "$wrt_hash"

    if [ -f "$mirrors_file" ]; then
        jq --tab 'map_values(map(select(test("\\.cn/|tencent|aliyun") | not)))' \
            "$mirrors_file" > "$mirrors_file.tmp"
        mv "$mirrors_file.tmp" "$mirrors_file"
    fi
    endgroup
    log_ok "Upstream commit: $wrt_hash"

    group "Update feeds"
    ./scripts/feeds update -a
    endgroup

    mkdir -p tmp
    if ! ./scripts/feeds install -a > tmp/.feeds-install.log 2>&1; then
        cat tmp/.feeds-install.log
        die "Feeds install failed"
    fi
    milestone "Feeds ready"
}

apply_customizations() {
    bash "$CUSTOMIZE_DIR/packages.sh" "$BUILD_PROFILE"
    bash "$CUSTOMIZE_DIR/files.sh" "$BUILD_PROFILE"
    milestone "Sources prepared"

    build_configs "$BUILD_PROFILE" | xargs -d '\n' cat >> .config
    bash "$CUSTOMIZE_DIR/patches.sh" "$BUILD_PROFILE"
    bash "$CUSTOMIZE_DIR/settings.sh" "$BUILD_PROFILE"
    bash "$CUSTOMIZE_DIR/defconfig.sh"
    milestone "$BUILD_PROFILE config applied"
}

# A failed download leaves a tiny error page behind instead of the archive
suspicious_downloads() {
    find dl -maxdepth 1 -type f -size -1024c | sort
}

download_sources() {
    local jobs
    local bad_files

    jobs=$(( $(nproc) * 2 ))
    if [ "$jobs" -gt 16 ]; then
        jobs=16
    fi

    section "Source Archives"
    group "make download"
    make download -j"$jobs"
    endgroup

    bad_files=$(suspicious_downloads)
    if [ -z "$bad_files" ]; then
        log_ok "All source archives downloaded"
        return 0
    fi

    log_warn "Download left files smaller than 1 KB, retrying them"
    xargs -d '\n' ls -l <<< "$bad_files"
    xargs -d '\n' rm -f <<< "$bad_files"

    group "make download (retry)"
    make download -j"$jobs"
    endgroup

    bad_files=$(suspicious_downloads)
    if [ -n "$bad_files" ]; then
        xargs -d '\n' ls -l <<< "$bad_files"
        die "Source archives are still smaller than 1 KB after the retry"
    fi

    log_ok "All source archives downloaded after the retry"
}

compile_cachebuilder() {
    section "Compile"
    group "make -j$(nproc)"
    if make -j"$(nproc)"; then
        endgroup
        milestone "Build succeeded on the first pass"
    else
        endgroup
        log_warn "Parallel build failed, retrying with make -j1 V=s"
        group "make -j1 V=s"
        make -j1 V=s
        endgroup
        milestone "Build succeeded on the verbose retry"
    fi

    set_env BUILD_OK true
}

assemble_imagebuilder() {
    local configs
    local package_removes
    local packages
    local rootfs_partsize
    local image_manifest

    rm -rf files bin

    bash "$CUSTOMIZE_DIR/files.sh" "$BUILD_PROFILE"
    bash "$CUSTOMIZE_DIR/settings.sh" "$BUILD_PROFILE"

    mapfile -t configs < <(build_configs "$BUILD_PROFILE")
    package_removes=$(sed -n 's/^# CONFIG_PACKAGE_\([^[:space:]]\{1,\}\) is not set$/-\1/p' \
        "${configs[@]}" | sort -u | tr '\n' ' ')
    packages="${package_removes}$(tr '\n' ' ' < .imagebuilder-packages)"
    rootfs_partsize=$(sed -n 's/^CONFIG_TARGET_ROOTFS_PARTSIZE=//p' .config | head -1)

    section "Assemble Firmware"
    make image \
        PROFILE=generic \
        PACKAGES="$packages" \
        FILES=files \
        ROOTFS_PARTSIZE="${rootfs_partsize:-512}"

    image_manifest=$(find ./bin -type f -name '*.manifest' -print -quit)
    [ -n "$image_manifest" ] || die "ImageBuilder manifest not found"

    if ! diff -u .imagebuilder-packages \
        <(awk 'NF >= 3 && $2 == "-" {print $1}' "$image_manifest" | sort -u); then
        die "Firmware packages differ from the ImageBuilder baseline"
    fi

    set_env BUILD_OK true
    milestone "ImageBuilder firmware ready"
}

restore_cache() {
    bash "$ARTIFACTS_DIR/cache.sh" restore "$BUILD_PROFILE" "$WRT_DIR"
}

publish_cache() {
    bash "$ARTIFACTS_DIR/cache.sh" publish "$BUILD_PROFILE" "$WRT_DIR"
}

publish_imagebuilder() {
    bash "$ARTIFACTS_DIR/imagebuilder.sh" publish "$BUILD_PROFILE" "$WRT_DIR"
}

publish_sdk() {
    bash "$ARTIFACTS_DIR/sdk.sh" publish "$BUILD_PROFILE" "$WRT_DIR"
}

check_apps() {
    bash "$ARTIFACTS_DIR/sdk.sh" check "$BUILD_PROFILE" "$IB_DIR"
}

build_apps() {
    bash "$ARTIFACTS_DIR/sdk.sh" build "$BUILD_PROFILE" "$WRT_DIR" "$IB_DIR"
}

deliver_firmware() {
    local build_minutes
    local build_duration
    local kernel_version
    local luci_branch
    local luci_version
    local firmware_path
    local firmware_name

    build_minutes=$(( ($(date +%s) - BUILD_START_TIME) / 60 ))
    build_duration="$((build_minutes % 60))min"
    if [ "$build_minutes" -ge 60 ]; then
        build_duration="$((build_minutes / 60))h$build_duration"
    fi

    kernel_version=$(find ./bin/targets -type f -name '*.manifest' \
        -exec grep -oP '^kernel - \K[\d\.]+' {} \; | head -1)
    kernel_version=${kernel_version:-unknown}

    if [ -f .imagebuilder-metadata.json ]; then
        luci_branch=$(jq -r '.wrt_branch // empty' .imagebuilder-metadata.json)
    fi
    luci_branch=${luci_branch:-$WRT_BRANCH}
    luci_version=${luci_branch#openwrt-}
    luci_version=${luci_version:-unknown}

    firmware_path=$(find ./bin/targets/x86 -type f -name '*-squashfs-combined-efi.img.gz' -print -quit)
    [ -n "$firmware_path" ] || die "Firmware image not found in bin/targets/x86"
    firmware_name="openwrt-$(echo "$BUILD_PROFILE" | tr '[:upper:]' '[:lower:]')-${TAG_TIME}-x86-64-efi.img.gz"

    mkdir -p ./upload
    cp -f "$firmware_path" "./upload/$firmware_name"
    milestone "Firmware ready: $firmware_name ($build_duration)"

    group "Upload firmware"
    rclone copy ./upload/ remote:/OpenWrt/ \
        --transfers=1 \
        --stats-one-line \
        --stats=20s
    endgroup
    log_ok "Firmware uploaded to remote:/OpenWrt/"

    # The firmware is already delivered, a failed notification must not fail the build
    if curl -fsS --retry 3 --max-time 30 -o /dev/null \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d photo='https://mirror.1991991.xyz/Picture/openwrt.webp' \
        -d parse_mode=Markdown \
        --data-urlencode "caption=#OpenWRT #${DEVICE_NAME}

*🎉 Ready to roll! Dive in! 🎉*

- 🌐 Kernel: ${kernel_version}

- 📦 LuCI: ${luci_version}

- ⌛ Build Duration: ${build_duration}

- 🔗 Firmware: [Click to View](${FIRMWARE_DOWNLOAD_URL})"; then
        log_ok "Notification sent"
    else
        log_warn "Notification failed"
    fi
}

usage() {
    local steps="${STEPS[*]}"

    printf 'Usage: %s <%s>\n' "$0" "${steps// /|}" >&2
}

main() {
    local step="${1:-}"
    local known

    for known in "${STEPS[@]}"; do
        if [ "$known" = "$step" ]; then
            "${step//-/_}"
            return
        fi
    done

    usage
    exit 1
}

main "$@"
