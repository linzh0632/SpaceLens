#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

release_parent="${SPACELENS_RELEASE_CHECK_PARENT:-${TMPDIR:-/tmp}}"
release_root="$(mktemp -d "$release_parent/SpaceLens-ReleaseCheck.XXXXXX")"
test_build="$release_root/tests"
derived_data="$release_root/derived"

plutil -lint Config/App-Info.plist Config/Preview-Info.plist >/dev/null

python3 - <<'PY'
import plistlib
from pathlib import Path
app = plistlib.loads(Path("Config/App-Info.plist").read_bytes())
preview = plistlib.loads(Path("Config/Preview-Info.plist").read_bytes())
assert "CFBundleDocumentTypes" not in app, "SpaceLens must remain preview-only"
assert app["CFBundleShortVersionString"] == preview["CFBundleShortVersionString"]
assert app["CFBundleVersion"] == preview["CFBundleVersion"]
attributes = preview["NSExtension"]["NSExtensionAttributes"]
assert "public.data" not in attributes["QLSupportedContentTypes"], "Do not claim every unknown data file"
assert preview["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.quicklook.preview"
print(f"Metadata: {app['CFBundleShortVersionString']} ({app['CFBundleVersion']}), preview-only")
PY

SPACELENS_TEST_BUILD="$test_build" ./scripts/test.sh
SPACELENS_DERIVED_DATA="$derived_data" ./scripts/build.sh

product="$derived_data/Build/Products/Release/SpaceLens.app"
app_info="$product/Contents/Info.plist"
preview_info="$product/Contents/PlugIns/SpaceLensPreview.appex/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_info")" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$preview_info")" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$app_info")" == "AppIcon" ]]
[[ -s "$product/Contents/Resources/AppIcon.icns" ]]
[[ -s "$product/Contents/Resources/Assets.car" ]]
if /usr/libexec/PlistBuddy -c 'Print :CFBundleDocumentTypes' "$app_info" >/dev/null 2>&1; then
    echo "Release app unexpectedly declares document opening roles." >&2
    exit 1
fi
architectures="$(lipo -archs "$product/Contents/MacOS/SpaceLens")"
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
    echo "Release app is not universal: $architectures" >&2
    exit 1
}
echo "Release check passed: tests, metadata, signing, preview-only associations, arm64 + x86_64."
echo "Build artifacts: $release_root"
