#!/bin/bash -e

set -eo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Build/Action/ImageBuilder.sh
source "$HERE/ImageBuilder.sh"

CACHE_ARTIFACT_TYPE='application/vnd.openwrt.cache.v2+tar+zstd'
CACHE_LAYOUT_VERSION=2
CACHE_PACKAGES_KEY='openwrt.packages-key'
CACHE_EXTRA=(tmp/go-build dl/go-mod-cache .ccache)

cache_prefix() {
    local profile

    profile=$(printf '%s' "${BUILD_PROFILE:?BUILD_PROFILE is required}" | tr '[:upper:]' '[:lower:]')
    printf 'build-%s-' "$profile"
}

cache_tag() {
    printf '%s%s-v%s' "$(cache_prefix)" "${TOOLCHAIN_KEY:?TOOLCHAIN_KEY is required}" "$CACHE_LAYOUT_VERSION"
}

cache_paths() (
    cd "$1" || exit 1

    for path in "${CACHE_EXTRA[@]}"; do
        if [ -e "$path" ]; then printf '%s\n' "$path"; fi
    done

    find staging_dir -maxdepth 1 \( -name 'host*' -o -name 'toolchain-*' \) 2>/dev/null || true
    exit 0
)

record_state() {
    printf 'CACHE_FRESH=%s\n' "$1" >> "${GITHUB_ENV:-/dev/null}"
}

restore() {
    local source_dir=${1:?Usage: BuildCache.sh restore <source-dir>}
    local ref
    local manifest
    local recorded

    require_dir "$source_dir" "OpenWrt source directory"
    require_command oras
    require_command jq
    require_command tar
    : "${PKG_KEY:?PKG_KEY is required}"

    make_workspace
    ref=$(package_ref "$(cache_tag)" cache)
    registry_login "$ref"

    section "Restore cache"

    if ! manifest=$(oras manifest fetch "$ref" 2>/dev/null); then
        record_state false
        log "cache: miss ($ref)"
        return 0
    fi

    group "Pull $ref"
    oras pull "$ref" --output "$WORKSPACE/pull"
    require_file "$WORKSPACE/pull/cache.tar.zst" "cache archive"
    tar --zstd -xpf "$WORKSPACE/pull/cache.tar.zst" -C "$source_dir"
    endgroup

    recorded=$(printf '%s' "$manifest" |
        jq -r --arg key "$CACHE_PACKAGES_KEY" '.annotations[$key] // empty')

    if [ "$recorded" = "$PKG_KEY" ]; then
        record_state true
        log "cache: hit ($ref)"
    else
        record_state false
        log "cache: hit ($ref), package set changed, refresh queued"
    fi
}

save() {
    local source_dir=${1:?Usage: BuildCache.sh save <source-dir>}
    local ref
    local cutoff

    if [ "${CACHE_FRESH:-false}" = 'true' ]; then
        log "cache: unchanged, upload skipped"
        return 0
    fi

    require_dir "$source_dir" "OpenWrt source directory"
    require_command oras
    require_command tar
    : "${PKG_KEY:?PKG_KEY is required}"

    make_workspace
    mkdir -p "$WORKSPACE/bundle"
    cache_paths "$source_dir" > "$WORKSPACE/paths"

    group "Pack $(wc -l < "$WORKSPACE/paths" | tr -d ' ') paths"
    tar --zstd -cpf "$WORKSPACE/bundle/cache.tar.zst" \
        -C "$source_dir" -T "$WORKSPACE/paths"
    endgroup

    ref=$(package_ref "$(cache_tag)" cache)
    cutoff=$(registry_cutoff)
    registry_login "$ref"

    group "Push $ref"
    (
        cd "$WORKSPACE/bundle"
        oras push "$ref" \
            --artifact-type "$CACHE_ARTIFACT_TYPE" \
            --annotation "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY}" \
            --annotation "org.opencontainers.image.created=$cutoff" \
            --annotation "$CACHE_PACKAGES_KEY=$PKG_KEY" \
            cache.tar.zst:application/zstd
    )
    prune_stale_versions "$ref" "$cutoff" "$(cache_prefix)"
    endgroup

    log "cache: pushed $ref ($(du -h "$WORKSPACE/bundle/cache.tar.zst" | cut -f1))"
}

usage() {
    printf "Usage: %s <restore|save> <source-dir>\n" "$0" >&2
}

main() {
    local action="${1:-}"
    shift || true

    case "$action" in
        restore) restore "$@" ;;
        save) save "$@" ;;
        *) usage; exit 1 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
