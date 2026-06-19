#!/bin/bash -e

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_profile "${1:?Usage: ApplySettings.sh <Router|Cloud>}"

SETTINGS_FILE="files/etc/uci-defaults/99-custom-settings"
CRONTAB_FILE="files/etc/crontabs/root"

begin_settings_file() {
    section "First Boot Setup"

    log "Generating uci-defaults settings"
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

    if is_enabled "${ENABLE_DUAL_WAN:-false}" && [ "${#DUAL_WAN_UCI_DEFAULTS[@]}" -gt 0 ]; then
        log "Dual WAN enabled, appending WAN2 configuration"
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
    chmod +x "$SETTINGS_FILE"
}

write_crontab() {
    local entry
    local guard_file
    local cron_line
    local label

    section "Scheduled Tasks"

    mkdir -p "$(dirname "$CRONTAB_FILE")"
    touch "$CRONTAB_FILE"

    for cron_line in "${CRON_ENTRIES[@]}"; do
        log "Adding crontab: $cron_line"
        echo "$cron_line" >> "$CRONTAB_FILE"
    done

    for entry in "${OPTIONAL_CRON_ENTRIES[@]}"; do
        IFS='|' read -r guard_file cron_line label <<< "$entry"
        [ -n "$guard_file" ] && [ -n "$cron_line" ] || continue

        if [ -x "$guard_file" ]; then
            log "Adding $label to crontabs"
            echo "$cron_line" >> "$CRONTAB_FILE"
        else
            log "Warning: $label dependency not found, skipping crontab"
        fi
    done
}

begin_settings_file
write_settings
finish_settings_file
write_crontab

log "ApplySettings.sh completed"
