#!/bin/bash

# Shared helpers: logging, checks and profile parsing
# Sourced, so every caller sets `set -eo pipefail` itself

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

if [ -t 1 ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    LOG_RED=$'\033[31m'
    LOG_GREEN=$'\033[32m'
    LOG_YELLOW=$'\033[33m'
    LOG_CYAN=$'\033[1;36m'
    LOG_RESET=$'\033[0m'
else
    LOG_RED="" LOG_GREEN="" LOG_YELLOW="" LOG_CYAN="" LOG_RESET=""
fi

section() {
    printf '\n%s▶ %s%s\n' "$LOG_CYAN" "$*" "$LOG_RESET"
}

milestone() {
    printf '%s══════════════════════════════════════════════════\n✓ %s%s\n' \
        "$LOG_GREEN" "$*" "$LOG_RESET"
}

group() {
    printf '::group::%s\n' "$*"
}

endgroup() {
    printf '::endgroup::\n'
}

log() {
    printf '  %s\n' "$*"
}

log_ok() {
    printf '  %s✓ %s%s\n' "$LOG_GREEN" "$*" "$LOG_RESET"
}

# GitHub Actions turns the ::warning:: and ::error:: commands into run annotations
log_warn() {
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        printf '::warning::%s\n' "$*"
    else
        printf '  %s⚠ %s%s\n' "$LOG_YELLOW" "$*" "$LOG_RESET"
    fi
}

# Reports on stderr so the message survives inside a command substitution
die() {
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        printf '::error::%s\n' "$*" >&2
    else
        printf '  %s✗ %s%s\n' "$LOG_RED" "$*" "$LOG_RESET" >&2
    fi
    exit 1
}

require_file() {
    [ -f "$1" ] || die "$2 not found: $1"
}

require_dir() {
    [ -d "$1" ] || die "$2 not found: $1"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 not found"
}

require_profile() {
    case "${1:-}" in
        Router|Cloud)
            ;;
        *)
            die "Unsupported build profile: ${1:-empty}"
            ;;
    esac
}

trim() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

# Splits "<left> => <right>" into RULE_LEFT and RULE_RIGHT
split_rule() {
    local line="$1"
    local kind="$2"

    [[ "$line" == *"=>"* ]] || die "Invalid $kind rule: $line"
    RULE_LEFT=$(trim "${line%%=>*}")
    RULE_RIGHT=$(trim "${line#*=>}")
    [ -n "$RULE_LEFT" ] && [ -n "$RULE_RIGHT" ] || die "Invalid $kind rule: $line"
}

set_config_value() {
    local section="$1"
    local key="$2"
    local value="$3"

    case "$section.$key" in
        profile.device_name)
            DEVICE_NAME="$value"
            ;;
        profile.default_ip)
            DEFAULT_IP="$value"
            ;;
        nikki.ui.url)
            NIKKI_UI_URL="$value"
            ;;
        nikki.ui.dest)
            NIKKI_UI_DEST="$value"
            ;;
        *)
            die "Unknown [$section] key: $key"
            ;;
    esac
}

# Rule arrays hold "<left>|<right>"; the right side comes last so it may contain "|"
parse_profile_config() {
    local file="$1"
    local section=""
    local raw_line
    local line
    local repo
    local dest_name
    local branch

    PACKAGE_CLONES=()
    PRIVATE_FILE_COPIES=()
    FILE_DOWNLOADS=()
    CRON_ENTRIES=()
    OPTIONAL_CRON_ENTRIES=()
    UCI_DEFAULTS=()
    DUAL_WAN_UCI_DEFAULTS=()

    DEVICE_NAME=""
    DEFAULT_IP=""
    NIKKI_UI_URL=""
    NIKKI_UI_DEST=""

    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        raw_line=${raw_line%$'\r'}

        if [[ "$raw_line" =~ ^[[:space:]]*\[([^]]+)\][[:space:]]*$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        # Shell sections are copied verbatim, comments and blank lines included
        case "$section" in
            uci)
                UCI_DEFAULTS+=("$raw_line")
                continue
                ;;
            uci.dual_wan)
                DUAL_WAN_UCI_DEFAULTS+=("$raw_line")
                continue
                ;;
        esac

        line=$(trim "$raw_line")
        [ -n "$line" ] || continue
        [[ "$line" = \#* ]] && continue

        case "$section" in
            profile|nikki.ui)
                set_config_value "$section" "$(trim "${line%%=*}")" "$(trim "${line#*=}")"
                ;;
            packages.clone)
                read -r repo dest_name branch <<< "$line"
                PACKAGE_CLONES+=("$repo|$branch|$dest_name")
                ;;
            private.copy)
                split_rule "$line" "copy"
                PRIVATE_FILE_COPIES+=("$RULE_LEFT|$RULE_RIGHT")
                ;;
            files.download)
                split_rule "$line" "download"
                FILE_DOWNLOADS+=("$RULE_LEFT|$RULE_RIGHT")
                ;;
            cron)
                CRON_ENTRIES+=("$line")
                ;;
            cron.if_exists)
                split_rule "$line" "optional cron"
                OPTIONAL_CRON_ENTRIES+=("$RULE_LEFT|$RULE_RIGHT")
                ;;
            "")
                ;;
            *)
                die "Unknown config section: [$section]"
                ;;
        esac
    done < "$file"
}

expand_config_vars() {
    local line="$1"
    local result=""
    local token
    local prefix
    local name
    local value
    local pattern='\$\{[A-Z_][A-Z_0-9]*\}|\$[A-Z_][A-Z_0-9]*'
    local names=(
        VLAN_ID_2 PPPOE_MAC_2 PPPOE_USERNAME_2 PPPOE_PASSWORD_2 PPPOE_WAN_MAC_2
        ROOT_PASSWORD_HASH
        VLAN_ID PPPOE_MAC PPPOE_USERNAME PPPOE_PASSWORD PPPOE_WAN_MAC
        DNS_FALLBACK_SERVER ROUTER_MAC SWITCH_MAC CLOUD_MAC LMINI_MAC
        REDIRECT_SRC_DPORT REDIRECT_DEST_PORT REDIRECT_ALLOW_IP
    )

    # Placeholders sit inside single quotes; expand once and keep the value literal
    while [[ "$line" =~ $pattern ]]; do
        token="${BASH_REMATCH[0]}"
        prefix="${line%%"$token"*}"
        line="${line#*"$token"}"
        name="${token#\$}"
        name="${name#\{}"
        name="${name%\}}"

        case " ${names[*]} " in
            *" $name "*)
                value="${!name-}"
                if [ -z "$value" ] && [ "$name" != REDIRECT_ALLOW_IP ]; then
                    die "Required setting is empty: $name"
                fi
                value=${value//\'/\'\\\'\'}
                result+="$prefix$value"
                ;;
            *)
                result+="$prefix$token"
                ;;
        esac
    done

    printf '%s' "$result$line"
}

# Profile names keep their capitals in the workflow and the private repo
profile_dir() {
    printf '%s/profiles/%s' "$REPO_ROOT" "${1,,}"
}

load_profile() {
    local profile="$1"
    local upstream_config="$REPO_ROOT/profiles/upstream.conf"
    local profile_config

    profile_config="$(profile_dir "$profile")/device.conf"

    require_file "$upstream_config" "upstream config"
    require_file "$profile_config" "profile config"

    # shellcheck disable=SC1090
    source "$upstream_config"
    parse_profile_config "$profile_config"

    BUILD_PROFILE="$profile"
}

# Usage: build_configs <profile>
build_configs() {
    printf '%s\n' "$REPO_ROOT/profiles/common/build.config" "$(profile_dir "$1")/build.config"
}

# Package names selected with =y in the profile's build configs
config_packages() {
    local configs

    mapfile -t configs < <(build_configs "$1")
    sed -n 's/^CONFIG_PACKAGE_\([^[:space:]=]\{1,\}\)=y$/\1/p' "${configs[@]}" | sort -u
}

is_enabled() {
    case "${1:-}" in
        true|yes|1|on)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
