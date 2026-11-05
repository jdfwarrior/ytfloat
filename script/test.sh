#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
TEST_FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
TEST_ARGS=(--disable-xctest --enable-swift-testing --build-system native --scratch-path "$PWD/.build/native" --disable-sandbox --cache-path "$PWD/.build/cache")
if [ -d "$TEST_FRAMEWORKS/Testing.framework" ]; then
  TEST_ARGS+=(-Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS" -Xlinker -F -Xlinker "$TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS")
fi
swift test "${TEST_ARGS[@]}"
