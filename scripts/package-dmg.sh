#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
derived="${SPACELENS_DERIVED_DATA:-${TMPDIR:-/tmp}/SpaceLens-DerivedData}"
output="${SPACELENS_DMG_DIR:-build/dmg}"
app="$derived/Build/Products/Release/SpaceLens.app"
preview="$app/Contents/PlugIns/SpaceLensPreview.appex"

# Refresh the Release build, then pack it. `release-check.sh` builds into its own temporary
# directory, so passing it here would only package whatever this script builds itself.
SPACELENS_DERIVED_DATA="$derived" ./scripts/build.sh

[[ -d "$preview" ]] || { echo "Missing preview extension in $app" >&2; exit 1; }
architectures="$(lipo -archs "$app/Contents/MacOS/SpaceLens")"
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
    echo "Release app is not universal: $architectures" >&2
    exit 1
}
codesign --verify --strict "$preview"
codesign --verify --strict "$app"
if /usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes' "$app/Contents/Info.plist" >/dev/null 2>&1; then
    echo "Release app unexpectedly declares document opening roles." >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
name="SpaceLens-$version.dmg"

# Stage the bundle together with an /Applications shortcut so the app can be dragged into place.
# The extension only registers reliably from /Applications, so the shortcut is part of the product.
staging="$(mktemp -d "${TMPDIR:-/tmp}/SpaceLens-DMG.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
# `ditto` instead of `cp -R`: it preserves the metadata the signature covers.
ditto "$app" "$staging/SpaceLens.app"
ln -s /Applications "$staging/Applications"

mkdir -p "$output"
rm -f "$output/$name"
# `hdiutil create` is deprecated on macOS 27; prefer the replacement and keep a fallback.
if ! diskutil image create from --volumeName "SpaceLens $version" --format UDZO \
        "$staging" "$output/$name" >/dev/null 2>&1; then
    hdiutil create -volname "SpaceLens $version" -srcfolder "$staging" -ov -format UDZO "$output/$name" >/dev/null
fi

echo "DMG: $output/$name  (version $version, build $build, $architectures)"
echo "sha256: $(shasum -a 256 "$output/$name" | awk '{print $1}')"
echo "The build is ad hoc signed, so downloads need the Gatekeeper steps in docs/INSTALL.md."
