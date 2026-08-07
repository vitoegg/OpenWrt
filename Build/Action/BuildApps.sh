#!/bin/bash -e

set -eo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Build/Action/ImageBuilder.sh
source "$HERE/ImageBuilder.sh"

SDK_ARTIFACT_TYPE='application/vnd.openwrt.sdk.v1+tar+zstd'

die() {
    log "ERROR: $*"
    exit 1
}

discover_apps() {
    local profile="$1" selected entry repo branch name

    selected=$(sed -n 's/^CONFIG_PACKAGE_\([^[:space:]=]\{1,\}\)=y$/\1/p' \
        "$GITHUB_WORKSPACE/Config/$profile.txt" 2>/dev/null) || return 0

    load_profile "$profile"
    for entry in "${PACKAGE_CLONES[@]}"; do
        IFS='|' read -r repo branch name <<< "$entry"
        name=${name:-${repo#*/}}
        if printf '%s\n' "$selected" | grep -qxF "$name"; then
            printf '%s\t%s\t%s\n' "$name" "$repo" "$branch"
        fi
    done
    return 0
}

upstream_commit() {
    git ls-remote "https://github.com/${1}.git" "${2:-HEAD}" 2>/dev/null |
        awk 'NR == 1 { print $1 }'
}

sdk_paths() (
    cd "$1" || exit 1

    for path in Makefile rules.mk Config.in .config feeds.conf feeds.conf.default \
        config include scripts tools target toolchain feeds dl build_dir/host \
        package/Makefile package/kernel package/toolchain; do
        if [ -e "$path" ]; then printf '%s\n' "$path"; fi
    done

    find staging_dir -maxdepth 1 \( -name host -o -name 'toolchain-*' \)
    find staging_dir -maxdepth 2 -type d -name pkginfo
    exit 0
)

publish() {
    local profile=${1:?Usage: BuildApps.sh publish <Router|Cloud> <source-dir>}
    local source_dir=${2:?Usage: BuildApps.sh publish <Router|Cloud> <source-dir>}
    local ref

    require_profile "$profile"
    require_dir "$source_dir" "OpenWrt source directory"
    require_command oras
    : "${WRT_HASH:?WRT_HASH is required}"

    make_workspace
    mkdir -p "$WORKSPACE/bundle"
    sdk_paths "$source_dir" > "$WORKSPACE/paths"

    for path in Makefile rules.mk Config.in config include scripts target \
        toolchain tools package/Makefile feeds staging_dir/host; do
        grep -qx "$path" "$WORKSPACE/paths" || die "$path missing from $source_dir"
    done

    tar --zstd -cpf "$WORKSPACE/bundle/sdk.tar.zst" \
        -C "$source_dir" -T "$WORKSPACE/paths"

    ref=$(package_ref "$profile" sdk)
    registry_login "$ref"
    (
        cd "$WORKSPACE/bundle"
        oras push "$ref" \
            --artifact-type "$SDK_ARTIFACT_TYPE" \
            --annotation "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY}" \
            --annotation "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
            --annotation "openwrt.profile=$profile" \
            --annotation "openwrt.wrt-hash=$WRT_HASH" \
            --annotation "openwrt.topdir=$source_dir" \
            sdk.tar.zst:application/zstd
    )
    prune_untagged_versions "$ref"

    log "SDK published: $ref ($(du -h "$WORKSPACE/bundle/sdk.tar.zst" | cut -f1))"
}

check() {
    local profile=${1:?Usage: BuildApps.sh check <Router|Cloud> <imagebuilder-dir>}
    local baseline="${2:?Usage: BuildApps.sh check <Router|Cloud> <imagebuilder-dir>}/.imagebuilder-apps.json"
    local stale='' name repo branch current recorded

    require_profile "$profile"
    require_command jq
    section "Custom apps"

    if [ "${FORCE_APPS:-false}" = 'true' ]; then
        stale=$(discover_apps "$profile" | cut -f1 | xargs)
        log "Forced rebuild: ${stale:-none}"
        printf 'STALE_APPS=%s\n' "$stale" | tee -a "${GITHUB_ENV:-/dev/null}"
        return 0
    fi

    while IFS=$'\t' read -r name repo branch; do
        recorded=$(jq -r --arg n "$name" '.[$n].commit // empty' "$baseline" 2>/dev/null)
        current=$(upstream_commit "$repo" "$branch")

        if [ -z "$recorded" ]; then
            log "  $name: not in baseline, keeping shipped build"
        elif [ -z "$current" ]; then
            log "  $name: upstream unreachable, keeping ${recorded:0:12}"
        elif [ "$current" = "$recorded" ]; then
            log "  $name: ${recorded:0:12} current"
        else
            log "  $name: ${recorded:0:12} -> ${current:0:12}"
            stale="${stale:+$stale }$name"
        fi
    done < <(discover_apps "$profile")

    if [ -n "$stale" ]; then
        log "Rebuilding: $stale"
    else
        log "All apps current"
    fi
    printf 'STALE_APPS=%s\n' "$stale" | tee -a "${GITHUB_ENV:-/dev/null}"
}

restore_sdk() {
    local profile="$1" sdk_dir="$2" ref topdir

    ref=$(package_ref "$profile" sdk)
    registry_login "$ref"

    topdir=$(oras manifest fetch "$ref" | jq -r '.annotations["openwrt.topdir"] // empty') ||
        die "cannot fetch $ref"
    [ "${topdir:-$sdk_dir}" = "$sdk_dir" ] ||
        die "SDK was built at $topdir, cannot use it at $sdk_dir"

    oras pull "$ref" --output "$WORKSPACE/sdk"
    require_file "$WORKSPACE/sdk/sdk.tar.zst" "SDK archive"
    tar --zstd -xpf "$WORKSPACE/sdk/sdk.tar.zst" -C "$sdk_dir"
    log "SDK restored to $sdk_dir"
}

build() {
    local profile=${1:?Usage: BuildApps.sh build <Router|Cloud> <sdk-dir> <imagebuilder-dir>}
    local sdk_dir=${2:?Usage: BuildApps.sh build <Router|Cloud> <sdk-dir> <imagebuilder-dir>}
    local ib_dir=${3:?Usage: BuildApps.sh build <Router|Cloud> <sdk-dir> <imagebuilder-dir>}
    local stale="${STALE_APPS:-}" name repo branch dest pkg

    [ -n "$stale" ] || { log "No stale apps"; return 0; }

    require_profile "$profile"
    require_dir "$ib_dir" "ImageBuilder directory"
    require_command oras

    make_workspace
    restore_sdk "$profile" "$sdk_dir"

    section "Clone apps"
    while IFS=$'\t' read -r name repo branch; do
        printf ' %s ' "$stale" | grep -qF " $name " || continue

        dest="$sdk_dir/package/custom/$name"
        rm -rf "$dest"
        git clone --depth=1 --single-branch ${branch:+--branch "$branch"} \
            "https://github.com/${repo}.git" "$dest"
        find "$dest" -mindepth 2 -maxdepth 2 -name Makefile -printf '%h\n'
    done < <(discover_apps "$profile") | sed 's|.*/||' | sort -u > "$WORKSPACE/packages"

    [ -s "$WORKSPACE/packages" ] || die "no package directories found in cloned apps"

    section "Scan packages"
    make -C "$sdk_dir" prepare-tmpinfo

    section "Compile apps"
    while IFS= read -r pkg; do
        log "Compiling $pkg"
        make -C "$sdk_dir" "package/$pkg/compile" \
            NO_DEPS=1 -j"$(nproc)" BUILD_LOG=1 || {
            dump_log "$sdk_dir" "$pkg"
            die "$pkg failed to build"
        }
    done < "$WORKSPACE/packages"

    replace_apks "$sdk_dir" "$ib_dir"
}

dump_log() {
    local file

    section "Build log: $2"
    while IFS= read -r file; do
        printf '\n===== %s =====\n' "$file"
        tail -n 60 "$file"
    done < <(find "$1/logs" -type f -name 'compile.txt' -path "*/$2/*" 2>/dev/null)
}

replace_apks() {
    local sdk_dir="$1" ib_dir="$2" apk name count=0

    section "Replace apks"
    while IFS= read -r apk; do
        name=$(basename "$apk")
        name=${name%-[0-9]*}

        find "$ib_dir/packages" -type f -name "$name-[0-9]*.apk" -delete
        cp "$apk" "$ib_dir/packages/"
        log "$(basename "$apk")"
        count=$((count + 1))
    done < <(find "$sdk_dir/bin/packages" -type f -name '*.apk' | sort)

    [ "$count" -gt 0 ] || die "no apks were produced"

    make -C "$ib_dir" package_index
    log "Replaced $count apks"
}

usage() {
    printf "Usage: %s <publish|check|build> <Router|Cloud> <dir>...\n" "$0" >&2
}

main() {
    local action="${1:-}"
    shift || true

    case "$action" in
        publish) publish "$@" ;;
        check) check "$@" ;;
        build) build "$@" ;;
        *) usage; exit 1 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
