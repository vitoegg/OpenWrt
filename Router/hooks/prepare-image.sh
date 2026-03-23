#!/bin/bash
set -euo pipefail

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [prepare-image] $*"
}

checksum_file() {
  local path=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path"
  else
    shasum -a 256 "$path"
  fi
}

TAG_TIME=${TAG_TIME:-$(TZ=Asia/Shanghai date +"%Y%m%d-%H%M")}
UPLOAD_DIR=upload
mkdir -p "$UPLOAD_DIR"

IMAGE_PATH=$(find ./bin/targets -type f -name '*-squashfs-combined-efi.img.gz' | head -n 1)
if [ -z "$IMAGE_PATH" ]; then
  IMAGE_PATH=$(find ./bin/targets -type f -name '*.img.gz' | head -n 1)
fi

if [ -z "$IMAGE_PATH" ]; then
  log "No firmware image found"
  exit 1
fi

IMAGE_NAME="openwrt-router-${TAG_TIME}-x86-64-efi.img.gz"
cp -f "$IMAGE_PATH" "$UPLOAD_DIR/$IMAGE_NAME"
cp -f ./.config "$UPLOAD_DIR/router-config-${TAG_TIME}.txt"

find ./builder -maxdepth 1 -type f -name '*.buildinfo' -exec cp -f {} "$UPLOAD_DIR/" \;
find ./bin/targets -type f \( -name '*.manifest' -o -name '*.kernel' -o -name 'profiles.json' \) -exec cp -f {} "$UPLOAD_DIR/" \;

checksum_file "$UPLOAD_DIR/$IMAGE_NAME" > "$UPLOAD_DIR/sha256sums"

{
  echo "build_time=${TAG_TIME}"
  echo "source_commit=$(git rev-parse HEAD)"
  echo "source_branch=$(git branch --show-current 2>/dev/null || true)"
  echo "image_name=${IMAGE_NAME}"
} > "$UPLOAD_DIR/build-info.txt"

log "Prepared firmware artifacts under ${UPLOAD_DIR}/"
