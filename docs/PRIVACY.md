# 隐私说明

SpaceLens 的预览处理完全在本机完成。

- 不创建账号，不包含遥测或分析服务。
- 不上传文件、文件名、目录结构或预览结果。
- 不加载文档中的远程资源。
- 唯一的网络请求是检查更新：开启后（默认关闭）在启动时向 GitHub Releases 查询最新版本号。该请求不附带文件、文件名、目录结构或使用数据；可在“通用设置”中关闭。与访问 GitHub 的普通网络请求一样，GitHub 仍会接收到建立连接所必需的网络信息，例如 IP 地址。
- 只读取 Finder 交给 Quick Look 的文件、文件夹或归档内容。
- 预览扩展是沙盒进程，为了跟随你在设置里选择的语言，它以只读方式读取本应用自身的偏好设置（仅“语言”一项，权限见 `Config/Preview.entitlements` 的只读共享偏好例外）。
- 不执行源代码、脚本、Notebook 单元格、文档宏或图表中的指令。
- ZIP 内的可预览条目直接在内存中读取，不会为了右侧预览解压到磁盘。

主应用不会写入或修改你的文件：它只读取 Finder 交给 Quick Look 的内容。应用只保存自身的偏好与扩展会话状态（语言、菜单栏图标、开机自启动、自动检查更新等），其中不包含文件内容、文件名或目录结构。卸载 SpaceLens 不会删除你的任何文件。

---

## English

SpaceLens processes previews locally on your Mac.

- It has no account system, telemetry, or analytics service.
- It does not upload file contents, file names, directory structures, or preview results.
- It does not load remote resources referenced by documents.
- Its only network request is an optional update check against GitHub Releases. Automatic checks are disabled by default and can be turned off in General settings. The request includes no file data, file names, directory structures, or usage events. As with any connection to GitHub, GitHub still receives network information required to serve the request, such as the IP address.
- It reads only the file, folder, or archive supplied by Finder through Quick Look.
- The sandboxed preview extension has read-only access to the app's preference domain solely to follow the selected interface language.
- It does not execute source code, scripts, notebook cells, document macros, or diagram instructions.
- Supported entries inside ZIP archives are read directly into bounded memory and are not extracted to disk for the detail preview.

The host app does not write to or modify user documents. It stores only its own preferences and extension-session state, such as the menu bar icon, launch at login, language, and update-check settings. These values contain no file content, file names, or directory structures. Uninstalling SpaceLens does not delete user files.
