#!/bin/bash -e

set -eo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/ImageBuilder.sh"

CACHE_ARTIFACT_TYPE='application/vnd.openwrt.buildcache.v1+tar+zstd'
CACHE_LAYERS=(toolchain ccache gocache dl)
CCACHE_MAX_SIZE='2.0G'
CCACHE_EVICT_AGE='14d'

normalize_mtimes() {
    local source_dir="$1"

    group "Normalize source mtimes"
    python3 - "$source_dir" <<'EOF'
import hashlib
import os
import subprocess
import sys

EPOCH = 978307200
RANGE = 400000000

root = sys.argv[1]
base_depth = root.rstrip(os.sep).count(os.sep)
repos = []
for dirpath, dirnames, _ in os.walk(root):
    if ".git" in dirnames or os.path.isfile(os.path.join(dirpath, ".git")):
        repos.append(dirpath)
    if dirpath.count(os.sep) - base_depth >= 3:
        dirnames[:] = []
    elif ".git" in dirnames:
        dirnames.remove(".git")

count = 0
for repo in repos:
    dirty = set()
    status = subprocess.run(
        ["git", "-C", repo, "status", "--porcelain", "-z", "--untracked-files=no"],
        capture_output=True, text=True, check=True).stdout
    for entry in status.split("\0"):
        if len(entry) > 3:
            dirty.add(entry[3:])

    listing = subprocess.run(
        ["git", "-C", repo, "ls-files", "-s", "-z"],
        capture_output=True, text=True, check=True).stdout
    for entry in listing.split("\0"):
        if not entry:
            continue
        meta, path = entry.split("\t", 1)
        mode, sha = meta.split(" ")[:2]
        if mode in ("120000", "160000"):
            continue
        target = os.path.join(repo, path)
        if path in dirty:
            try:
                with open(target, "rb") as handle:
                    sha = hashlib.md5(handle.read()).hexdigest()
            except OSError:
                continue
        mtime = EPOCH + int(sha[:8], 16) % RANGE
        try:
            os.utime(target, (mtime, mtime))
        except OSError:
            continue
        count += 1

print(f"Normalized {count} files")
EOF
    endgroup
}

configure_ccache() {
    local ccache_dir="$1/.ccache"

    mkdir -p "$ccache_dir"
    cat > "$ccache_dir/ccache.conf" <<EOF
max_size = $CCACHE_MAX_SIZE
compiler_check = content
EOF
}

cache_paths() (
    local layer="$1" source_dir="$2"

    cd "$source_dir" || exit 1

    case "$layer" in
        toolchain)
            find staging_dir -mindepth 1 -maxdepth 1 \
                \( -name host -o -name hostpkg -o -name 'toolchain-*' \) 2>/dev/null || true
            find build_dir/host build_dir/hostpkg build_dir/toolchain-* -maxdepth 2 \
                \( -name '.prepared*' -o -name '.configured*' -o -name '.built*' \) 2>/dev/null || true
            ;;
        ccache)
            if [ -d .ccache ]; then printf '.ccache\n'; fi
            ;;
        gocache)
            if [ -d tmp/go-build ]; then printf 'tmp/go-build\n'; fi
            ;;
        dl)
            if [ -d dl ]; then printf 'dl\n'; fi
            ;;
    esac
    exit 0
)

discard_layers() {
    local target_dir="$1"

    rm -rf "$target_dir/staging_dir" "$target_dir/build_dir" \
        "$target_dir/.ccache" "$target_dir/tmp/go-build" "$target_dir/dl"
}

restore_layers() {
    local profile="$1" target_dir="$2"
    local ref manifest cache_profile cache_branch layer restored=true

    if is_enabled "${CLEAN_BUILD:-}"; then
        log "Clean build requested, skipping cache restore"
        return 0
    fi

    ref=$(package_ref "$profile" cache)
    registry_login "$ref"

    if ! manifest=$(oras manifest fetch "$ref" 2>/dev/null); then
        log "Build cache unavailable: $ref, starting cold"
        return 0
    fi

    cache_profile=$(jq -r '.annotations["openwrt.profile"] // empty' <<< "$manifest")
    cache_branch=$(jq -r '.annotations["openwrt.wrt-branch"] // empty' <<< "$manifest")
    if [ "$cache_profile" != "$profile" ] || [ "$cache_branch" != "${WRT_BRANCH:-}" ]; then
        log "Build cache mismatch (profile ${cache_profile:-empty}, branch ${cache_branch:-empty}), starting cold"
        return 0
    fi

    make_workspace
    group "Pull $ref"
    oras pull "$ref" --output "$WORKSPACE/cache" || restored=false
    endgroup

    if [ "$restored" = true ]; then
        for layer in "${CACHE_LAYERS[@]}"; do
            if [ ! -f "$WORKSPACE/cache/$layer.tar.zst" ]; then
                continue
            fi
            group "Restore $layer"
            tar --zstd -xpf "$WORKSPACE/cache/$layer.tar.zst" -C "$target_dir" || restored=false
            endgroup
            if [ "$restored" != true ]; then
                break
            fi
        done
    fi

    if [ "$restored" != true ]; then
        discard_layers "$target_dir"
        log "Build cache restore failed, starting cold"
        return 0
    fi

    log "Build cache restored: $ref ($(jq -r '.annotations["openwrt.wrt-hash"] // "unknown"' <<< "$manifest"))"
}

restore() {
    local profile=${1:?Usage: BuildCache.sh restore <Router|Cloud> <source-dir>}
    local target_dir=${2:?Usage: BuildCache.sh restore <Router|Cloud> <source-dir>}

    require_profile "$profile"
    require_dir "$target_dir" "OpenWrt source directory"
    require_command oras
    require_command jq
    require_command python3

    normalize_mtimes "$target_dir"
    restore_layers "$profile" "$target_dir"
    configure_ccache "$target_dir"
}

publish() {
    local profile=${1:?Usage: BuildCache.sh publish <Router|Cloud> <source-dir>}
    local source_dir=${2:?Usage: BuildCache.sh publish <Router|Cloud> <source-dir>}
    local layer ref cutoff
    local files=()

    require_profile "$profile"
    require_dir "$source_dir" "OpenWrt source directory"
    require_command oras
    : "${WRT_HASH:?WRT_HASH is required}"

    make_workspace
    mkdir -p "$WORKSPACE/bundle"

    if [ -f "$source_dir/scripts/dl_cleanup.py" ] && [ -d "$source_dir/dl" ]; then
        group "Clean stale downloads"
        # dl_cleanup.py resolves dl/ and build_dir/ relative to the cwd
        (cd "$source_dir" && python3 scripts/dl_cleanup.py dl) ||
            log "WARNING: dl cleanup failed"
        endgroup
    fi

    if command -v ccache >/dev/null 2>&1 && [ -d "$source_dir/.ccache" ]; then
        CCACHE_DIR="$source_dir/.ccache" ccache --evict-older-than "$CCACHE_EVICT_AGE" >/dev/null ||
            log "WARNING: ccache eviction failed"
    fi

    for layer in "${CACHE_LAYERS[@]}"; do
        cache_paths "$layer" "$source_dir" | LC_ALL=C sort > "$WORKSPACE/$layer.paths"
        if [ ! -s "$WORKSPACE/$layer.paths" ]; then
            continue
        fi
        group "Pack $layer"
        tar --sort=name -I 'zstd -T0 -3' -cpf "$WORKSPACE/bundle/$layer.tar.zst" \
            -C "$source_dir" -T "$WORKSPACE/$layer.paths"
        endgroup
        files+=("$layer.tar.zst:application/zstd")
    done
    [ "${#files[@]}" -gt 0 ] || die "no cache layers to publish"

    ref=$(package_ref "$profile" cache)
    cutoff=$(registry_cutoff)
    registry_login "$ref"
    group "Push $ref"
    (
        cd "$WORKSPACE/bundle"
        oras push "$ref" \
            --artifact-type "$CACHE_ARTIFACT_TYPE" \
            --annotation "org.opencontainers.image.source=https://github.com/${GITHUB_REPOSITORY}" \
            --annotation "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
            --annotation "openwrt.profile=$profile" \
            --annotation "openwrt.wrt-hash=$WRT_HASH" \
            --annotation "openwrt.wrt-branch=${WRT_BRANCH:-}" \
            "${files[@]}"
    )
    prune_stale_versions "$ref" "$cutoff"
    endgroup

    log "Build cache published: $ref ($(du -sh "$WORKSPACE/bundle" | cut -f1))"
}

usage() {
    printf "Usage: %s <restore|publish> <Router|Cloud> <dir>\n" "$0" >&2
}

main() {
    local action="${1:-}"
    shift || true

    case "$action" in
        restore) restore "$@" ;;
        publish) publish "$@" ;;
        *) usage; exit 1 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
