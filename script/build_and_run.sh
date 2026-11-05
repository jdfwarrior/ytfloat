#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2;; esac
if [ -x dist/YTFloat.app/Contents/Helpers/ytfloat ]; then dist/YTFloat.app/Contents/Helpers/ytfloat --quit || true; fi
for attempt in {1..30}; do if ! pgrep -x YTFloat >/dev/null; then break; fi; sleep 0.1; done
if pgrep -x YTFloat >/dev/null; then
  pkill -x YTFloat
  for attempt in {1..30}; do if ! pgrep -x YTFloat >/dev/null; then break; fi; sleep 0.1; done
fi
./script/build.sh
APP="$PWD/dist/YTFloat.app"
if [ "$MODE" = --debug ]; then exec lldb -- "$APP/Contents/MacOS/YTFloat"; fi
/usr/bin/open "$APP"
case "$MODE" in
  --verify)
    for attempt in {1..40}; do
      if "$APP/Contents/Helpers/ytfloat" --status 2>/dev/null; then exit 0; fi
      sleep 0.1
    done
    echo 'YTFloat did not become ready' >&2; exit 1;;
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "YTFloat"';;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.ytfloat.YTFloat"';;
esac
