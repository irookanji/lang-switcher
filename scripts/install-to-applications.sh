#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

"$root/scripts/build-app.sh"

pkill -x LangSwitcher 2>/dev/null || true
sleep 0.5

ditto "$root/LangSwitcher.app" "/Applications/LangSwitcher.app"
xattr -cr "/Applications/LangSwitcher.app" 2>/dev/null || true

echo "Installed /Applications/LangSwitcher.app"
echo "Remove the copy in the project folder if you no longer need it:"
echo "  $root/LangSwitcher.app"
echo ""
echo "Open System Settings and allow THIS app in both:"
echo "  Device Control and Data Access"
echo "  Input Monitoring"

open -a "/Applications/LangSwitcher.app"
