#!/bin/bash
# Builds LangSwitcher.app and LangSwitcher-arm64.app.zip for GitHub Releases.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

"$root/scripts/build-app.sh"
rm -f "$root/LangSwitcher-arm64.app.zip"
staging="$root/.release-staging"
rm -rf "$staging"
mkdir -p "$staging"
ditto "$root/LangSwitcher.app" "$staging/LangSwitcher.app"
cp "$root/docs/INSTALL-FIRST-TIME.txt" "$staging/"
ditto -c -k --sequesterRsrc --keepParent "$staging" "$root/LangSwitcher-arm64.app.zip"
rm -rf "$staging"
echo "Created $root/LangSwitcher-arm64.app.zip ($(du -h "$root/LangSwitcher-arm64.app.zip" | awk '{print $1}'))"
