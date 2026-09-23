#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --scratch-path "${SPACELENS_TEST_BUILD:-${TMPDIR:-/tmp}/SpaceLens-TestBuild}"
