#!/bin/bash -e

set -eo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Build/Action/ImageBuilder.sh
source "$HERE/ImageBuilder.sh"

CACHE_ARTIFACT_TYPE='application/vnd.openwrt.cache.v1+tar+zstd'
CACHE_KINDS=(dl toolchain ccache)

cache_spec() {
    local profile

    profile=$(printf '%s' "${BUILD_PROFILE:?BUILD_PROFILE is required}" | tr '[:upper:]' '[:lower:]')

    case "${1:-}" in
        dl) printf 'dl-%s\tdl-' "${WRT_BRANCH#openwrt-}" ;;
        toolchain) printf 'toolchain-%.12s\ttoolchain-' "$WRT_HASH" ;;
        ccache) printf 'ccache-%s\tccache-%s' "$profile" "$profile" ;;
        *) die "Unsupported cache kind: ${1:-empty}" ;;
    esac
}

cache_paths() {
    case "$1" in
        dl)
            if [ -d dl ]; then printf 'dl\n'; fi
            ;;
        toolchain)
            find staging_dir -maxdepth 1 \
                \( -name 'host*' -o -name 'toolchain-*' \) 2>/dev/null || true
            ;;
        ccache)
            if [ -d .ccache ]; then printf '.ccache\n'; fi
            ;;
    esac
}

cache_size() (
    set +o pipefail
    cd "$2" 2>/dev/null || true
    cache_paths "$1" | tr '\n' '\0' | xargs -0 -r du -sk 2>/dev/null |
        awk '{ total += $1 } END { printf "%d", total + 0 }'
)

record_size() {
    printf '%s_CACHE_SIZE=%s\n' "${1^^}" "$2" >> "${GITHUB_ENV:-/dev/null}"
}

restore_one() {
    local kind="$1" source_dir="$2" spec tag ref

    spec=$(cache_spec "$kind")
    IFS=$'\t' read -r tag _ <<< "$spec"
    ref=$(package_ref "$tag" cache)

    if ! oras manifest fetch "$ref" >/dev/null 2>&1; then
        record_size "$kind" ""
        log "$kind cache: miss ($ref)"
        return 0
    fi

    group "Pull $ref"
    rm -rf "$WORKSPACE/pull"
    oras pull "$ref" --output "$WORKSPACE/pull"
    require_file "$WORKSPACE/pull/cache.tar.zst" "$kind cache archive"
    tar --zstd -xpf "$WORKSPACE/pull/cache.tar.zst" -C "$source_dir"
    endgroup

    record_size "$kind" "$(cache_size "$kind" "$source_dir")"
    log "$kind cache: hit ($ref)"
}

restore() {
    local source_dir=${1:?Usage: BuildCache.sh restore <source-dir>}
    local kind

    require_dir "$source_dir" "OpenWrt source directory"
    require_command oras
    require_command tar

    make_workspace
    registry_login "$(package_ref dl cache)"

    section "Restore caches"
    for kind in "${CACHE_KINDS[@]}"; do
        restore_one "$kind" "$source_dir"
    done
}

save() {
    local kind=${1:?Usage: BuildCache.sh save <dl|toolchain|ccache> <source-dir>}
    local source_dir=${2:?Usage: BuildCache.sh save <dl|toolchain|ccache> <source-dir>}
    local spec tag prefix ref cutoff size before size_var

    require_dir "$source_dir" "OpenWrt source directory"
    require_command oras
    require_command tar

    spec=$(cache_spec "$kind")
    IFS=$'\t' read -r tag prefix <<< "$spec"
    size_var="${kind^^}_CACHE_SIZE"
    before="${!size_var-}"
    size=$(cache_size "$kind" "$source_dir")

    if [ "$size" -eq 0 ]; then
        log "$kind cache: nothing to upload"
        return 0
    fi

    if [ "$size" = "$before" ]; then
        log "$kind cache: unchanged, upload skipped"
        return 0
    fi

    make_workspace
    mkdir -p "$WORKSPACE/bundle"
    ( cd "$source_dir" && cache_paths "$kind" ) > "$WORKSPACE/paths"

    group "Pack $kind cache"
    tar --zstd -cpf "$WORKSPACE/bundle/cache.tar.zst" \
        -C "$source_dir" -T "$WORKSPACE/paths"
    endgroup

    ref=$(package_ref "$tag" cache)
    cutoff=$(registry_cutoff)
    registry_login "$ref"

    group "Push $ref"
    (
        cd "$WORKSPACE/bundle"
        oras push "$ref" \
            --artifact-type "$CACHE_ARTIFACT_TYPE" \
            --annotation "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY}" \
            --annotation "org.opencontainers.image.created=$cutoff" \
            cache.tar.zst:application/zstd
    )
    prune_stale_versions "$ref" "$cutoff" "$prefix"
    endgroup

    log "$kind cache: pushed $ref ($(du -h "$WORKSPACE/bundle/cache.tar.zst" | cut -f1))"
}

usage() {
    printf "Usage: %s <restore <source-dir>|save <dl|toolchain|ccache> <source-dir>>\n" "$0" >&2
}

main() {
    local action="${1:-}"
    shift || true

    : "${WRT_BRANCH:?WRT_BRANCH is required}"
    : "${WRT_HASH:?WRT_HASH is required}"

    case "$action" in
        restore) restore "$@" ;;
        save) save "$@" ;;
        *) usage; exit 1 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
