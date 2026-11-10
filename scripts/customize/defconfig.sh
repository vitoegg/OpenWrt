#!/bin/bash

# Runs make defconfig and prunes feed packages with broken dependencies

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"

MAX_PRUNE_ROUNDS=8
DEFCONFIG_LOG="tmp/.defconfig.log"

# Output is kept in $DEFCONFIG_LOG, intermediate runs would repeat pruned warnings
run_defconfig() {
    mkdir -p tmp
    if ! make defconfig -j"$(nproc)" > "$DEFCONFIG_LOG" 2>&1; then
        cat "$DEFCONFIG_LOG"
        die "make defconfig failed"
    fi
}

# Selected packages built from a feed source given as <feed>/<package>
selected_packages_of() {
    awk -v src="package/feeds/$1/Makefile" '
        FNR == NR {
            if ($1 == "Source-Makefile:") cur = $2
            else if ($1 == "Package:" && cur == src) pkgs[$2] = 1
            next
        }
        /^CONFIG_PACKAGE_[^=]+=[ym]$/ {
            sub(/^CONFIG_PACKAGE_/, ""); sub(/=[ym]$/, "")
            if ($0 in pkgs) print
        }
    ' tmp/.packageinfo .config
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

for ((round = 1; ; round++)); do
    broken=$(broken_feed_packages | sort -u)
    [ -n "$broken" ] || break

    if [ "$round" -gt "$MAX_PRUNE_ROUNDS" ]; then
        printf '%s\n' "$broken"
        die "Broken feed packages remain after $MAX_PRUNE_ROUNDS rounds"
    fi

    # Pruning an unselected source cannot change the selection, a selected one is a real breakage
    while IFS= read -r entry; do
        selected=$(selected_packages_of "$entry" | paste -sd, -)
        [ -z "$selected" ] || die "Cannot prune $entry ($(prune_reason "$entry")): selected $selected"
        rm -f "package/feeds/$entry"
        log_ok "Pruned $entry ($(prune_reason "$entry"))"
    done <<< "$broken"

    run_defconfig
done

group "make defconfig"
cat "$DEFCONFIG_LOG"
endgroup

if grep -qiE 'warning|recursive dependency' "$DEFCONFIG_LOG"; then
    die "make defconfig still reports warnings"
fi

log_ok "$(grep -cE '^CONFIG_PACKAGE_[^=]+=[ym]$' .config) packages selected"
