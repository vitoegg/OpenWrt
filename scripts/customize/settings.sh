#!/bin/bash

# Generates the first-boot uci-defaults script and the root crontab

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/core.sh"

load_profile "${1:?Usage: settings.sh <Router|Cloud>}"

SETTINGS_FILE="files/etc/uci-defaults/99-custom-settings"
CRONTAB_FILE="files/etc/crontabs/root"

begin_settings_file() {
    section "First Boot Settings"

    : "${ROOT_PASSWORD_HASH:?ROOT_PASSWORD_HASH is required}"
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    cat > "$SETTINGS_FILE" <<SETTINGS
#!/bin/sh

# Set Password
sed -i 's|root:::0:99999:7:::|root:$ROOT_PASSWORD_HASH:20211:0:99999:7:::|g' /etc/shadow

SETTINGS
}

write_lines() {
    local line

    for line in "$@"; do
        line=$(expand_config_vars "$line")
        printf '%s\n' "$line" >> "$SETTINGS_FILE"
    done
}

write_settings() {
    if [ "${#UCI_DEFAULTS[@]}" -gt 0 ]; then
        write_lines "${UCI_DEFAULTS[@]}"
    fi

    if is_enabled "${ENABLE_DUAL_WAN:-}" && [ "${#DUAL_WAN_UCI_DEFAULTS[@]}" -gt 0 ]; then
        log_ok "Dual WAN settings appended"
        if [ "${#UCI_DEFAULTS[@]}" -gt 0 ]; then
            local last_index
            last_index=$((${#UCI_DEFAULTS[@]} - 1))
            [ -z "${UCI_DEFAULTS[$last_index]}" ] || printf '\n' >> "$SETTINGS_FILE"
        fi
        write_lines "${DUAL_WAN_UCI_DEFAULTS[@]}"
    fi
}

finish_settings_file() {
    echo "exit 0" >> "$SETTINGS_FILE"
    sh -n "$SETTINGS_FILE"
    chmod +x "$SETTINGS_FILE"
    log_ok "$SETTINGS_FILE ($(wc -l < "$SETTINGS_FILE" | tr -d '[:space:]') lines)"
}

write_crontab() {
    local entry
    local guard_file
    local cron_line

    section "Scheduled Tasks"

    mkdir -p "$(dirname "$CRONTAB_FILE")"
    touch "$CRONTAB_FILE"

    for cron_line in "${CRON_ENTRIES[@]}"; do
        echo "$cron_line" >> "$CRONTAB_FILE"
        log_ok "$cron_line"
    done

    for entry in "${OPTIONAL_CRON_ENTRIES[@]}"; do
        IFS='|' read -r guard_file cron_line <<< "$entry"

        if [ -x "$guard_file" ]; then
            echo "$cron_line" >> "$CRONTAB_FILE"
            log_ok "$cron_line"
        else
            log_warn "$guard_file not found, crontab entry skipped"
        fi
    done
}

begin_settings_file
write_settings
finish_settings_file
write_crontab
