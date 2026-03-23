#!/bin/bash
set -euo pipefail

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [prepare-compile] $*"
}

if [ -n "${WRT_COMMIT:-}" ]; then
  log "Checking out pinned commit: ${WRT_COMMIT}"
  git fetch --depth=1 origin "${WRT_COMMIT}"
  git checkout --detach FETCH_HEAD
fi

PROJECT_MIRRORS_FILE='./scripts/projectsmirrors.json'
if [ -f "$PROJECT_MIRRORS_FILE" ]; then
  log "Removing regional mirrors from ${PROJECT_MIRRORS_FILE}"
  sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$PROJECT_MIRRORS_FILE"
fi

log "OpenWrt source commit: $(git rev-parse HEAD)"
