#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" != --no-build ]; then ./script/build.sh; fi
APP="$PWD/dist/YTFloat.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo 'Expected a numeric major.minor.patch app version' >&2; exit 1; fi
if [ -n "${RELEASE_TAG:-}" ] && [ "$RELEASE_TAG" != "v$VERSION" ]; then
  echo "Release tag $RELEASE_TAG does not match app version v$VERSION" >&2; exit 1
fi
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
lipo "$APP/Contents/MacOS/YTFloat" -verify_arch "$ARCH"
lipo "$APP/Contents/Helpers/ytfloat" -verify_arch "$ARCH"
codesign --verify --deep --strict "$APP"
"$APP/Contents/Helpers/ytfloat" --version
mkdir -p dist/releases
ARCHIVE="YTFloat-${VERSION}-macOS-${ARCH}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/releases/$ARCHIVE"
(cd dist/releases && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
printf 'Packaged dist/releases/%s\n' "$ARCHIVE"
