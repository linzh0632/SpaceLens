#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
module_cache="${SPACELENS_MODULE_CACHE:-${TMPDIR:-/tmp}/SpaceLens-ModuleCache}"
SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" CLANG_MODULE_CACHE_PATH="$module_cache" \
    swift test --disable-sandbox --scratch-path "${SPACELENS_TEST_BUILD:-${TMPDIR:-/tmp}/SpaceLens-TestBuild}"
