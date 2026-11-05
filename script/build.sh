#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIGURATION:-release}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
SDK_FLAGS=()
SDK_MAJOR="$(xcrun --sdk macosx --show-sdk-version | cut -d. -f1)"
if [ "$SDK_MAJOR" -ge 27 ]; then SDK_FLAGS=(-Xswiftc -DYTFLOAT_SDK_27); fi
swift build --build-system native --scratch-path "$PWD/.build/native" -c "$CONFIG" --disable-sandbox --cache-path "$PWD/.build/cache" "${SDK_FLAGS[@]}"
BIN="$(swift build --build-system native --scratch-path "$PWD/.build/native" -c "$CONFIG" --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache")"
APP="$PWD/dist/YTFloat.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/YTFloat" "$APP/Contents/MacOS/YTFloat"
cp "$BIN/ytfloat-cli" "$APP/Contents/Helpers/ytfloat"
cp Config/Info.plist "$APP/Contents/Info.plist"
cp Config/YTFloat.icns "$APP/Contents/Resources/YTFloat.icns"
rm -rf "$APP/Contents/Resources/YTFloat_YTFloat.bundle" "$APP/Contents/Resources/Resources"
cp -R Sources/YTFloat/Resources "$APP/Contents/Resources/Resources"
if [ "$CONFIG" = release ]; then
  strip -x "$APP/Contents/MacOS/YTFloat" "$APP/Contents/Helpers/ytfloat"
fi
codesign --force --sign - "$APP/Contents/Helpers/ytfloat"
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
du -sh "$APP"
