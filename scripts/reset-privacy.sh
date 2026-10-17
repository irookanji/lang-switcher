#!/bin/bash
# Clears macOS privacy entries for Lang Switcher so you can re-allow the current build.
set -euo pipefail

echo "Closing Lang Switcher if it is running…"
pkill -x LangSwitcher 2>/dev/null || true

if ! command -v tccutil >/dev/null 2>&1; then
    echo "tccutil not found. Remove LangSwitcher manually in System Settings instead."
    exit 1
fi

echo "Resetting privacy entries for local.langswitcher…"
tccutil reset Accessibility local.langswitcher 2>/dev/null || true
tccutil reset ListenEvent local.langswitcher 2>/dev/null || true
tccutil reset PostEvent local.langswitcher 2>/dev/null || true

xattr -cr /Applications/LangSwitcher.app 2>/dev/null || true

cat <<'EOF'

Next steps (important):

1. Open Finder → Applications → LangSwitcher.app
   If macOS warns the app is from an unidentified developer:
   Right-click → Open → Open (once).

2. Launch the app. In the dialog, click "Open System Settings" (NOT Deny).

3. System Settings → Privacy & Security:
   • Device Control and Data Access → LangSwitcher ON
   • Input Monitoring → LangSwitcher ON
   (Use + and pick /Applications/LangSwitcher.app if it is not listed.)

4. Menu bar → Lang Switcher → Quit. Open the app again from Applications.

The menu must show Accessibility: granted and Input Monitoring: granted.

EOF
