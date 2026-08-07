#!/bin/bash -e

set -eo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Build/Action/ImageBuilder.sh
source "$HERE/ImageBuilder.sh"

SDK_ARTIFACT_TYPE='application/vnd.openwrt.sdk.v1+tar+zstd'
SDK_REQUIRED=(Makefile rules.mk Config.in config include scripts target
              toolchain tools package/Makefile feeds)
SDK_EXTRA=(.config feeds.conf feeds.conf.default dl tmp/go-build
          package/kernel package/toolchain)
SDK_STAGING=(staging_dir/host staging_dir/hostpkg build_dir/hostpkg)
SDK_HOST_TOOLS=(jsmin po2lmo)

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
        awk 'NR == 1 { print $1 }' || true
}

sdk_paths() (
    cd "$1" || exit 1

    for path in "${SDK_REQUIRED[@]}" "${SDK_EXTRA[@]}"; do
        if [ -e "$path" ]; then printf '%s\n' "$path"; fi
    done

    find staging_dir -maxdepth 1 \( -name 'host*' -o -name 'toolchain-*' \) 2>/dev/null || true
    find build_dir -maxdepth 1 -name 'host*' 2>/dev/null || true
    find staging_dir -maxdepth 2 -type d -name pkginfo 2>/dev/null || true
    exit 0
)

publish() {
    local profile=${1:?Usage: BuildApps.sh publish <Router|Cloud> <source-dir>}
    local source_dir=${2:?Usage: BuildApps.sh publish <Router|Cloud> <source-dir>}
    local path ref cutoff

    require_profile "$profile"
    require_dir "$source_dir" "OpenWrt source directory"
    require_command oras
    : "${WRT_HASH:?WRT_HASH is required}"

    make_workspace
    mkdir -p "$WORKSPACE/bundle"
    sdk_paths "$source_dir" > "$WORKSPACE/paths"

    for path in "${SDK_REQUIRED[@]}" "${SDK_STAGING[@]}"; do
        grep -qx "$path" "$WORKSPACE/paths" || die "$path missing from $source_dir"
    done

    for path in "${SDK_HOST_TOOLS[@]}"; do
        [ -x "$source_dir/staging_dir/hostpkg/bin/$path" ] ||
            die "host tool $path missing, LuCI packages cannot be rebuilt"
    done

    group "Pack $(wc -l < "$WORKSPACE/paths" | tr -d ' ') paths"
    tar --zstd -cpf "$WORKSPACE/bundle/sdk.tar.zst" \
        -C "$source_dir" -T "$WORKSPACE/paths"
    endgroup

    ref=$(package_ref "$profile" sdk)
    cutoff=$(registry_cutoff)
    registry_login "$ref"
    group "Push $ref"
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
    prune_stale_versions "$ref" "$cutoff"
    endgroup

    log "SDK published: $ref ($(du -h "$WORKSPACE/bundle/sdk.tar.zst" | cut -f1))"
}

emit_stale() {
    local stale="$1"

    if [ -n "$stale" ]; then
        log "Rebuilding: $stale"
    else
        log "All apps up to date"
    fi
    printf 'STALE_APPS=%s\n' "$stale" >> "${GITHUB_ENV:-/dev/null}"
}

report_app() {
    local line
    printf -v line '%-17s %-26s %s' "$1" "$2" "$3"
    log "$line"
}

check() {
    local profile=${1:?Usage: BuildApps.sh check <Router|Cloud> <imagebuilder-dir>}
    local ib_dir=${2:?Usage: BuildApps.sh check <Router|Cloud> <imagebuilder-dir>}
    local baseline="$ib_dir/.imagebuilder-apps.json"
    local stale='' name repo branch current recorded source

    require_profile "$profile"
    require_command jq
    section "Custom apps"

    if [ "${FORCE_APPS:-false}" = 'true' ]; then
        emit_stale "$(discover_apps "$profile" | cut -f1 | xargs)"
        return 0
    fi

    while IFS=$'\t' read -r name repo branch; do
        recorded=$(jq -r --arg n "$name" '.[$n].commit // empty' "$baseline" 2>/dev/null || true)
        current=$(upstream_commit "$repo" "$branch")
        source="$repo${branch:+@$branch}"

        if [ -z "$recorded" ]; then
            report_app "$name" "$source" "not in baseline, keeping shipped build"
        elif [ -z "$current" ]; then
            report_app "$name" "$source" "${recorded:0:12}  upstream unreachable, keeping shipped build"
        elif [ "$current" = "$recorded" ]; then
            report_app "$name" "$source" "${recorded:0:12}  up to date"
        else
            report_app "$name" "$source" "${recorded:0:12} -> ${current:0:12}  rebuild"
            stale="${stale:+$stale }$name"
        fi
    done < <(discover_apps "$profile")

    emit_stale "$stale"
}

restore_sdk() {
    local profile="$1" sdk_dir="$2" ref topdir

    ref=$(package_ref "$profile" sdk)
    registry_login "$ref"

    topdir=$(oras manifest fetch "$ref" | jq -r '.annotations["openwrt.topdir"] // empty') ||
        die "cannot fetch $ref"
    [ "${topdir:-$sdk_dir}" = "$sdk_dir" ] ||
        die "SDK was built at $topdir, cannot use it at $sdk_dir"

    group "Pull $ref"
    oras pull "$ref" --output "$WORKSPACE/sdk"
    require_file "$WORKSPACE/sdk/sdk.tar.zst" "SDK archive"

    mkdir -p "$sdk_dir"
    find "$sdk_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    tar --zstd -xpf "$WORKSPACE/sdk/sdk.tar.zst" -C "$sdk_dir"
    endgroup

    log "SDK restored to $sdk_dir ($(du -sh "$sdk_dir" | cut -f1))"
}

dump_log() {
    local sdk_dir="$1" pkg="$2" file found=''

    section "Build log: $pkg"
    while IFS= read -r file; do
        printf '\n===== %s =====\n' "$file"
        tail -n 60 "$file"
        found=1
    done < <(find "$sdk_dir/logs" -type f -name 'compile.txt' -path "*/$pkg/*" 2>/dev/null)

    [ -n "$found" ] || log "No compile log found for $pkg"
}

replace_apks() {
    local sdk_dir="$1" ib_dir="$2" apk name dest
    local built=() stale=()

    section "Replace apks"
    mapfile -t built < <(find "$sdk_dir/bin/packages" -type f -name '*.apk' 2>/dev/null | sort)
    [ "${#built[@]}" -gt 0 ] || die "no apks were produced"

    for apk in "${built[@]}"; do
        name=$(basename "$apk")
        name=${name%-[0-9]*}

        mapfile -t stale < <(find "$ib_dir/packages" -type f -name "$name-[0-9]*.apk" | sort)
        if [ "${#stale[@]}" -gt 0 ]; then
            dest=$(dirname "${stale[0]}")
            rm -f "${stale[@]}"
        else
            dest="$ib_dir/packages"
        fi

        cp "$apk" "$dest/"
        log "$(basename "$apk") -> ${dest#"$ib_dir/"}"
    done

    group "make package_index"
    make -C "$ib_dir" package_index
    endgroup

    log "Replaced ${#built[@]} apks"
}

build() {
    local profile=${1:?Usage: BuildApps.sh build <Router|Cloud> <sdk-dir> <imagebuilder-dir>}
    local sdk_dir=${2:?Usage: BuildApps.sh build <Router|Cloud> <sdk-dir> <imagebuilder-dir>}
    local ib_dir=${3:?Usage: BuildApps.sh build <Router|Cloud> <sdk-dir> <imagebuilder-dir>}
    local stale="${STALE_APPS:-}" name repo branch dest pkg
    local packages=()

    if [ -z "$stale" ]; then
        log "No stale apps"
        return 0
    fi

    require_profile "$profile"
    require_dir "$ib_dir" "ImageBuilder directory"
    require_command oras

    make_workspace
    restore_sdk "$profile" "$sdk_dir"

    section "Clone apps"
    while IFS=$'\t' read -r name repo branch; do
        case " $stale " in
            *" $name "*) ;;
            *) continue ;;
        esac

        dest="$sdk_dir/package/custom/$name"
        rm -rf "$dest"
        group "Clone $repo"
        git clone --depth=1 --single-branch ${branch:+--branch "$branch"} \
            "https://github.com/${repo}.git" "$dest"
        endgroup
        log "$name: $(git -C "$dest" rev-parse --short HEAD)"
    done < <(discover_apps "$profile")

    mapfile -t packages < <(
        for name in $stale; do
            find "$sdk_dir/package/custom/$name" -mindepth 2 -maxdepth 2 \
                -name Makefile -printf '%P\n' 2>/dev/null
        done | sed 's|/Makefile$||' | sort -u
    )
    [ "${#packages[@]}" -gt 0 ] || die "no package directories found in cloned apps"

    section "Scan packages"
    group "make prepare-tmpinfo"
    make -C "$sdk_dir" prepare-tmpinfo
    endgroup
    log "Found ${#packages[@]} packages: ${packages[*]}"

    section "Compile apps"
    for pkg in "${packages[@]}"; do
        group "Compile $pkg"
        make -C "$sdk_dir" "package/$pkg/compile" \
            NO_DEPS=1 -j"$(nproc)" BUILD_LOG=1 || {
            endgroup
            dump_log "$sdk_dir" "$pkg"
            die "$pkg failed to build"
        }
        endgroup
        log "$pkg built"
    done

    replace_apks "$sdk_dir" "$ib_dir"
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
