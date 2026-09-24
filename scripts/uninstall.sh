#!/bin/bash
set -euo pipefail
install_dir="${SPACELENS_INSTALL_DIR:-/Applications}"
target="$install_dir/SpaceLens.app"
trash_dir="${SPACELENS_TRASH_DIR:-$HOME/.Trash}"
if [[ "${1:-}" != "--remove" ]]; then
    echo "Usage: ./scripts/uninstall.sh --remove" >&2
    echo "The app will be moved to Trash after its identity is verified." >&2
    exit 2
fi
[[ -e "$target" ]] || { echo "SpaceLens is not installed at $target"; exit 0; }
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist")
[[ "$bundle_id" == "io.github.linzh0632.SpaceLens" ]] || {
    echo "Refusing to remove an app with a different identity." >&2
    exit 1
}
if pgrep -x SpaceLens >/dev/null; then
    echo "Quit SpaceLens before uninstalling it." >&2
    exit 1
fi
extension="$target/Contents/PlugIns/SpaceLensPreview.appex"
if [[ "${SPACELENS_SKIP_REGISTRATION:-0}" != "1" && -e "$extension" ]]; then
    pluginkit -r "$extension" || true
fi
mkdir -p "$trash_dir"
destination="$trash_dir/SpaceLens.app"
if [[ -e "$destination" ]]; then
    destination="$trash_dir/SpaceLens-$(date +%Y%m%d-%H%M%S).app"
fi
mv "$target" "$destination"
echo "Moved SpaceLens to: $destination"
echo "Source code and user files were not changed."
