#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
sdk="$(xcrun --show-sdk-path)"
mkdir -p "$root/.build"

if [[ ! -f "$root/AppIcon.icns" ]]; then
    "$root/scripts/build-icon.sh"
fi

swiftc -sdk "$sdk" -target arm64-apple-macosx10.15 -O \
    -module-name LangSwitcherCore \
    -emit-module -emit-module-path "$root/.build/LangSwitcherCore.swiftmodule" \
    -emit-library -o "$root/.build/libLangSwitcherCore.dylib" \
    -framework Carbon \
    "$root"/Sources/LangSwitcherCore/*.swift
install_name_tool -id @rpath/libLangSwitcherCore.dylib "$root/.build/libLangSwitcherCore.dylib"

swiftc -sdk "$sdk" -target arm64-apple-macosx10.15 -O \
    -I "$root/.build" -L "$root/.build" -lLangSwitcherCore \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -framework AppKit -framework ApplicationServices -framework Carbon -framework Foundation \
    -o "$root/.build/LangSwitcher" \
    "$root"/Sources/LangSwitcher/*.swift

app="$root/LangSwitcher.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
cp "$root/.build/LangSwitcher" "$app/Contents/MacOS/LangSwitcher"
cp "$root/.build/libLangSwitcherCore.dylib" "$app/Contents/Frameworks/"
cp "$root/wordlists/en.txt" "$root/wordlists/sv.txt" "$root/wordlists/ru.txt" "$app/Contents/Resources/"
cp "$root/wordlists/NOTICE" "$app/Contents/Resources/WORDLIST-NOTICE"
cp "$root/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LangSwitcher</string>
    <key>CFBundleIdentifier</key>
    <string>local.langswitcher</string>
    <key>CFBundleName</key>
    <string>Lang Switcher</string>
    <key>CFBundleDisplayName</key>
    <string>Lang Switcher</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Lang Switcher watches the keys you type so it can switch among English, Swedish, and Russian.</string>
    <key>NSListenEventUsageDescription</key>
    <string>Lang Switcher reads key presses to detect which language you are typing.</string>
</dict>
</plist>
EOF

codesign --force --sign - --deep --entitlements "$root/LangSwitcher.entitlements" "$app"
echo "Built $app"
