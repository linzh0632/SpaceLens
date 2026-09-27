#!/bin/bash
# Prints the release notes for one version: the matching CHANGELOG section, the install steps that
# apply to an ad hoc signed image, and the checksum of the built disk image.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: release-notes.sh <version> <dmg>}"
dmg="${2:?usage: release-notes.sh <version> <dmg>}"

python3 - "$version" <<'PY'
import pathlib
import re
import sys

version = sys.argv[1]
text = pathlib.Path("CHANGELOG.md").read_text(encoding="utf-8")
match = re.search(rf"^## {re.escape(version)}\b[^\n]*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
print(match.group(1).rstrip() if match else "See CHANGELOG.md for the change list.")
PY

cat <<'TEXT'

## 安装 / Install

1. 打开 DMG，把 **SpaceLens** 拖到 **Applications**（必须放在这里，Quick Look 扩展才会稳定注册）。
   Open the DMG and drag **SpaceLens** into **Applications**; the extension only registers reliably from there.
2. 首次打开会被 Gatekeeper 拦下：本版本为 **ad hoc 签名**，未经 Apple Developer ID 签名与公证。
   请**按住 Control 点击 SpaceLens → 打开**，或在终端执行：
   The image is ad hoc signed and not notarized, so Gatekeeper blocks the first launch. Control-click
   SpaceLens and choose Open, or run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/SpaceLens.app
   ```
3. 启动一次 SpaceLens（启动时会确认预览扩展已启用），之后即可用空格预览。
   Launch SpaceLens once; after that, space previews are handled by SpaceLens.
TEXT

echo
echo "sha256: \`$(shasum -a 256 "$dmg" | awk '{print $1}')\`"
