#!/bin/bash -e

BUILD_FLOW_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$BUILD_FLOW_DIR/../.." && pwd)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

section() {
    echo ""
    echo "========== $1 =========="
}

require_file() {
    local file="$1"
    local label="$2"

    if [ ! -f "$file" ]; then
        log "ERROR: ${label} not found: $file"
        exit 1
    fi
}

require_dir() {
    local dir="$1"
    local label="$2"

    if [ ! -d "$dir" ]; then
        log "ERROR: ${label} not found: $dir"
        exit 1
    fi
}

trim() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

append_copy_rule() {
    local line="$1"
    local source_path
    local dest_path
    local label

    if [[ "$line" != *"=>"* ]]; then
        log "ERROR: Invalid copy rule: $line"
        exit 1
    fi

    source_path=$(trim "${line%%=>*}")
    dest_path=$(trim "${line#*=>}")
    label=${source_path##*/}

    [ -n "$source_path" ] && [ -n "$dest_path" ] || return 0
    PRIVATE_SCRIPT_COPIES+=("$source_path|$dest_path|$label")
}

append_download_rule() {
    local line="$1"
    local url
    local dest_path

    if [[ "$line" != *"=>"* ]]; then
        log "ERROR: Invalid download rule: $line"
        exit 1
    fi

    url=$(trim "${line%%=>*}")
    dest_path=$(trim "${line#*=>}")

    [ -n "$url" ] && [ -n "$dest_path" ] || return 0
    FILE_DOWNLOADS+=("$url|$dest_path")
}

append_optional_cron() {
    local line="$1"
    local guard_file
    local cron_line
    local label

    if [[ "$line" != *"=>"* ]]; then
        log "ERROR: Invalid optional cron rule: $line"
        exit 1
    fi

    guard_file=$(trim "${line%%=>*}")
    cron_line=$(trim "${line#*=>}")
    label=${guard_file##*/}

    [ -n "$guard_file" ] && [ -n "$cron_line" ] || return 0
    OPTIONAL_CRON_ENTRIES+=("$guard_file|$cron_line|$label")
}

append_clone_rule() {
    local line="$1"
    local repo
    local dest_name
    local branch

    read -r repo dest_name branch <<< "$line"
    [ -n "$repo" ] || return 0
    PACKAGE_CLONES+=("$repo|${branch:-}|${dest_name:-}")
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
        argon.background.source)
            ARGON_BACKGROUND_SOURCE="$value"
            ;;
        argon.background.dest)
            ARGON_BACKGROUND_DEST="$value"
            ;;
        *)
            if [ "$section" = "profile" ]; then
                log "ERROR: Unknown profile key: $key"
            else
                log "ERROR: Unknown [$section] key: $key"
            fi
            exit 1
            ;;
    esac
}

parse_profile_config() {
    local file="$1"
    local section=""
    local raw_line
    local line
    local key
    local value

    PACKAGE_REMOVES=()
    PACKAGE_CLONES=()
    PRIVATE_SCRIPT_COPIES=()
    FILE_DOWNLOADS=()
    CRON_ENTRIES=()
    OPTIONAL_CRON_ENTRIES=()
    UCI_DEFAULTS=()
    DUAL_WAN_UCI_DEFAULTS=()

    DEVICE_NAME=""
    DEFAULT_IP=""
    ENABLE_DUAL_WAN="${ENABLE_DUAL_WAN:-false}"
    NIKKI_UI_URL=""
    NIKKI_UI_DEST=""
    ARGON_BACKGROUND_SOURCE=""
    ARGON_BACKGROUND_DEST=""

    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        raw_line=${raw_line%$'\r'}

        if [[ "$raw_line" =~ ^[[:space:]]*\[([^]]+)\][[:space:]]*$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        case "$section" in
            uci|uci.dual_wan)
                line="${raw_line%$'\r'}"
                if [ "$section" = "uci" ]; then
                    UCI_DEFAULTS+=("$line")
                else
                    DUAL_WAN_UCI_DEFAULTS+=("$line")
                fi
                ;;
            *)
                line=$(trim "$raw_line")
                [ -n "$line" ] || continue
                [[ "$line" = \#* ]] && continue

                case "$section" in
                    profile|nikki.ui|argon.background)
                        key=$(trim "${line%%=*}")
                        value=$(trim "${line#*=}")
                        set_config_value "$section" "$key" "$value"
                        ;;
                    packages.remove)
                        PACKAGE_REMOVES+=("$line")
                        ;;
                    packages.clone)
                        append_clone_rule "$line"
                        ;;
                    private.copy)
                        append_copy_rule "$line"
                        ;;
                    files.download)
                        append_download_rule "$line"
                        ;;
                    cron)
                        CRON_ENTRIES+=("$line")
                        ;;
                    cron.if_exists)
                        append_optional_cron "$line"
                        ;;
                    "")
                        ;;
                    *)
                        log "ERROR: Unknown config section: [$section]"
                        exit 1
                        ;;
                esac
                ;;
        esac
    done < "$file"
}

expand_config_vars() {
    local line="$1"
    local name
    local value
    local names=(
        VLAN_ID_2 PPPOE_MAC_2 PPPOE_USERNAME_2 PPPOE_PASSWORD_2 PPPOE_WAN_MAC_2
        ROOT_PASSWORD_HASH
        VLAN_ID PPPOE_MAC PPPOE_USERNAME PPPOE_PASSWORD PPPOE_WAN_MAC
        DNS_FALLBACK_SERVER ROUTER_MAC SWITCH_MAC
        REDIRECT_SRC_DPORT REDIRECT_DEST_PORT
    )

    for name in "${names[@]}"; do
        value="${!name-}"
        line="${line//\$$name/$value}"
        line="${line//\$\{$name\}/$value}"
    done

    printf '%s' "$line"
}

load_profile() {
    local profile="$1"
    local upstream_config="$REPO_ROOT/Build/upstream.conf"
    local profile_config="$REPO_ROOT/Custom/${profile}.conf"

    require_file "$upstream_config" "upstream config"
    require_file "$profile_config" "profile config"

    # shellcheck disable=SC1090
    source "$upstream_config"
    parse_profile_config "$profile_config"

    BUILD_PROFILE="$profile"
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
