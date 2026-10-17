#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
sdk="$(xcrun --show-sdk-path)"
mkdir -p "$root/.build"

swiftc -sdk "$sdk" -target arm64-apple-macosx10.15 \
    -module-name LangSwitcherCore \
    -emit-module -emit-module-path "$root/.build/LangSwitcherCore.swiftmodule" \
    -emit-library -o "$root/.build/libLangSwitcherCore.dylib" \
    -framework Carbon \
    "$root"/Sources/LangSwitcherCore/*.swift
install_name_tool -id @rpath/libLangSwitcherCore.dylib "$root/.build/libLangSwitcherCore.dylib"

swiftc -sdk "$sdk" -target arm64-apple-macosx10.15 \
    -I "$root/.build" -L "$root/.build" -lLangSwitcherCore \
    -Xlinker -rpath -Xlinker @executable_path \
    -framework Carbon -framework Foundation \
    -o "$root/.build/LangSwitcherChecks" \
    "$root"/Tests/LangSwitcherChecks/main.swift

"$root/.build/LangSwitcherChecks"
