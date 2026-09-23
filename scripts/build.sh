#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep signed bundles outside synced/File Provider folders, which may add FinderInfo.
derived="${SPACELENS_DERIVED_DATA:-${TMPDIR:-/tmp}/SpaceLens-DerivedData}"
xcodebuild -project SpaceLens.xcodeproj -scheme SpaceLens -configuration Release -derivedDataPath "$derived" build
app="$derived/Build/Products/Release/SpaceLens.app"
codesign --verify --strict --verbose=2 "$app/Contents/PlugIns/SpaceLensPreview.appex"
codesign --verify --strict --verbose=2 "$app"
printf '\nBuilt: %s\n' "$app"
