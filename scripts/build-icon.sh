#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source="$root/AppIcon-source.png"
iconset="$root/AppIcon.iconset"
icns="$root/AppIcon.icns"

if [[ ! -f "$source" ]]; then
    echo "Missing $source"
    exit 1
fi

rm -rf "$iconset"
mkdir -p "$iconset"

build_size() {
    local size="$1"
    local name="$2"
    sips -z "$size" "$size" "$source" --out "$iconset/$name" >/dev/null
}

build_size 16 icon_16x16.png
build_size 32 icon_16x16@2x.png
build_size 32 icon_32x32.png
build_size 64 icon_32x32@2x.png
build_size 128 icon_128x128.png
build_size 256 icon_128x128@2x.png
build_size 256 icon_256x256.png
build_size 512 icon_256x256@2x.png
build_size 512 icon_512x512.png
build_size 1024 icon_512x512@2x.png

iconutil -c icns "$iconset" -o "$icns"
echo "Built $icns"
