#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_DEST="${1:-$HOME/Applications/YTFloat.app}"
CLI_DIR="${2:-$HOME/.local/bin}"
if [ ! -d dist/YTFloat.app ]; then ./script/build.sh; fi
if [ "${APP_DEST##*/}" != YTFloat.app ]; then echo 'Destination must end in YTFloat.app' >&2; exit 2; fi
mkdir -p "$(dirname "$APP_DEST")" "$CLI_DIR"
APP_DEST="$(cd "$(dirname "$APP_DEST")" && pwd)/YTFloat.app"
CLI_DIR="$(cd "$CLI_DIR" && pwd)"
if [ -x "$APP_DEST/Contents/Helpers/ytfloat" ]; then "$APP_DEST/Contents/Helpers/ytfloat" --quit || true; sleep 0.3; fi
ditto dist/YTFloat.app "$APP_DEST"
ln -sfn "$APP_DEST/Contents/Helpers/ytfloat" "$CLI_DIR/ytfloat"
printf 'Installed %s\nCLI: %s/ytfloat\n' "$APP_DEST" "$CLI_DIR"
case ":$PATH:" in *":$CLI_DIR:"*) ;; *) printf 'Add this directory to your PATH: %s\n' "$CLI_DIR";; esac
