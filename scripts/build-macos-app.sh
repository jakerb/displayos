#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/DisplayOS.app"
BUILD="$ROOT/apps/host-macos/.build/release/DisplayOS"

cd "$ROOT/apps/host-macos"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build-cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build-cache/swiftpm"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD" "$APP/Contents/MacOS/DisplayOS"
cp "$ROOT/apps/host-macos/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
