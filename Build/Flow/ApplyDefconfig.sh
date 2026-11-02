#!/bin/bash -e

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

MAX_PRUNE_ROUNDS=8
DEFCONFIG_LOG="tmp/.defconfig.log"

# Output is kept in $DEFCONFIG_LOG, intermediate runs would repeat pruned warnings
run_defconfig() {
    mkdir -p tmp
    if ! make defconfig -j"$(nproc)" > "$DEFCONFIG_LOG" 2>&1; then
        cat "$DEFCONFIG_LOG"
        log "ERROR: make defconfig failed"
        exit 1
    fi
}

selected_packages() {
    grep -E '^CONFIG_PACKAGE_[^=]+=[ym]$' .config | sort || true
}

# Maps a package name to <feed>/<package> when it comes from an installed feed
feed_source_of() {
    awk -v pkg="$1" '
        /^Source-Makefile: / { src = $2 }
        $1 == "Package:" && $2 == pkg { print src; exit }
    ' tmp/.packageinfo | sed -n 's|^package/feeds/\([^/]*/[^/]*\)/Makefile$|\1|p'
}

# Feed packages that defconfig reported with a missing or recursive dependency
broken_feed_packages() {
    local symbol

    sed -n "s|.*WARNING: Makefile 'package/feeds/\([^/]*/[^/]*\)/Makefile' has a .*dependency on .*|\1|p" \
        "$DEFCONFIG_LOG"
    sed -n '/recursive dependency detected/{n;s/.*symbol PACKAGE_\([^ ]*\) .*/\1/p;}' "$DEFCONFIG_LOG" |
        while IFS= read -r symbol; do
            feed_source_of "$symbol"
        done
}

prune_reason() {
    local deps

    deps=$(sed -n "s|.*WARNING: Makefile 'package/feeds/$1/Makefile' has a .*dependency on '\([^']*\)'.*|\1|p" \
        "$DEFCONFIG_LOG" | sort -u | paste -sd, -)
    printf '%s' "${deps:+missing $deps}"
    [ -n "$deps" ] || printf 'recursive dependency'
}

section "Defconfig"

run_defconfig
selected_packages > tmp/.selected-before

for ((round = 1; ; round++)); do
    broken=$(broken_feed_packages | sort -u)
    [ -n "$broken" ] || break

    if [ "$round" -gt "$MAX_PRUNE_ROUNDS" ]; then
        log "ERROR: Broken feed packages remain after $MAX_PRUNE_ROUNDS rounds"
        printf '%s\n' "$broken"
        exit 1
    fi

    while IFS= read -r entry; do
        rm -f "package/feeds/$entry"
        log "Pruned: $entry ($(prune_reason "$entry"))"
    done <<< "$broken"

    run_defconfig
done

echo "::group::make defconfig"
cat "$DEFCONFIG_LOG"
echo "::endgroup::"

selected_packages > tmp/.selected-after
if ! diff -u tmp/.selected-before tmp/.selected-after; then
    log "ERROR: Pruning changed the selected packages"
    exit 1
fi

log "ApplyDefconfig.sh completed"
