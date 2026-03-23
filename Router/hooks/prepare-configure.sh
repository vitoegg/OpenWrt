#!/bin/bash
set -euo pipefail

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [prepare-configure] $*"
}

ROUTER_ROOT=${ROUTER_ROOT:-${GITHUB_WORKSPACE:-}/Router}
if [ -z "${ROUTER_ROOT}" ] || [ ! -d "${ROUTER_ROOT}/Scripts" ]; then
  log "Router 脚本目录不存在: ${ROUTER_ROOT:-unset}"
  exit 1
fi

run_local_script() {
  local script_name=$1
  log "Running ${script_name}"
  bash "${ROUTER_ROOT}/Scripts/${script_name}"
}

run_local_script Packages.sh
run_local_script Prepare.sh
run_local_script Settings.sh

log "prepare-configure completed"
