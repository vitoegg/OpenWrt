#!/bin/bash
set -euo pipefail

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [prepare-configure] $*"
}

SCRIPT_BASE_URL=${ROUTER_SCRIPT_BASE_URL:-}
if [ -z "$SCRIPT_BASE_URL" ]; then
  log "ROUTER_SCRIPT_BASE_URL is required"
  exit 1
fi

run_remote_script() {
  local script_name=$1
  local temp_file
  temp_file=$(mktemp)
  log "Downloading ${script_name} from ${SCRIPT_BASE_URL}"
  wget -q -O "$temp_file" "${SCRIPT_BASE_URL}/${script_name}"
  chmod +x "$temp_file"
  log "Running ${script_name}"
  bash "$temp_file"
  rm -f "$temp_file"
}

run_remote_script Packages.sh
run_remote_script Prepare.sh
run_remote_script Settings.sh

log "prepare-configure completed"
