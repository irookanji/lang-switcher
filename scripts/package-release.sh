#!/bin/bash
# Builds LangSwitcher.app and LangSwitcher-arm64.app.zip for GitHub Releases.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

"$root/scripts/build-app.sh"
rm -f "$root/LangSwitcher-arm64.app.zip"
ditto -c -k --sequesterRsrc --keepParent "$root/LangSwitcher.app" "$root/LangSwitcher-arm64.app.zip"
echo "Created $root/LangSwitcher-arm64.app.zip ($(du -h "$root/LangSwitcher-arm64.app.zip" | awk '{print $1}'))"
