#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
derived="${SPACELENS_DERIVED_DATA:-${TMPDIR:-/tmp}/SpaceLens-DerivedData}"
source_app="$derived/Build/Products/Release/SpaceLens.app"
target="${SPACELENS_INSTALL_DIR:-/Applications}/SpaceLens.app"
# `release-check.sh` builds into its own temporary directory, so passing it does not refresh the
# build installed here. Warn instead of silently installing a stale bundle.
if [[ -e "$source_app" ]]; then
    stale=$(find Sources Config -type f -newer "$source_app" -print -quit)
    if [[ -n "$stale" ]]; then
        echo "Warning: $source_app is older than $stale; run ./scripts/build.sh first." >&2
    fi
fi
codesign --verify --strict "$source_app/Contents/PlugIns/SpaceLensPreview.appex"
codesign --verify --strict "$source_app"
if [[ -e "$target" ]]; then
    if [[ "${1:-}" != "--replace" ]]; then
        echo 'SpaceLens already exists. Quit it, then rerun with --replace.' >&2
        exit 1
    fi
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist")
    [[ "$bundle_id" == 'io.github.linzh0632.SpaceLens' ]] || { echo 'Refusing to replace a different app.' >&2; exit 1; }
    if pgrep -x SpaceLens >/dev/null; then
        echo 'Quit SpaceLens before replacing it.' >&2
        exit 1
    fi
    backup=$(mktemp -d "${TMPDIR:-/tmp}/SpaceLens-backup.XXXXXX")
    mv "$target" "$backup/SpaceLens.previous"
    echo "Previous version preserved at $backup/SpaceLens.previous"
    trap 'echo "Install failed; prior version is preserved at $backup/SpaceLens.previous" >&2' ERR
fi
mkdir -p "$(dirname "$target")"
# Avoid copying Finder/resource-fork metadata into signed bundles.
ditto --norsrc --noextattr "$source_app" "$target"
codesign --verify --strict "$target/Contents/PlugIns/SpaceLensPreview.appex"
codesign --verify --strict "$target"
open "$target"
pluginkit -r "$source_app/Contents/PlugIns/SpaceLensPreview.appex" || true
pluginkit -a "$target/Contents/PlugIns/SpaceLensPreview.appex"
echo "Installed: $target"
echo 'Enable SpaceLens in System Settings > Login Items & Extensions > Quick Look if needed.'
