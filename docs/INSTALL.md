# 安装 SpaceLens

SpaceLens 当前版本为 **0.9.1（构建 24）**。目前没有已签名、公证的二进制安装包，需要使用完整 Xcode 从源码构建。构建出的通用应用以 macOS 12 为最低运行目标，但当前源码使用 Xcode 26 的 Icon Composer 图标格式，因此构建机器需要 macOS 15.6 或更高版本。

## 准备环境

1. 安装 Xcode 26 或更高版本。
2. 首次打开 Xcode，同意许可协议并等待必要组件安装完成。
3. 在终端确认开发工具可用：

```sh
xcodebuild -version
swift --version
```

## 构建并安装

```sh
git clone https://github.com/linzh0632/SpaceLens.git
cd SpaceLens
./scripts/build.sh
./scripts/install.sh
```

应用默认安装到 `/Applications/SpaceLens.app`，安装脚本使用本地 ad hoc 签名，不需要付费开发者账号。macOS 可能要求你允许写入“应用程序”文件夹。

安装完成后，在 Finder 中选中一个文件夹并按空格。如果仍显示系统默认信息面板，请前往“系统设置 → 通用 → 登录项与扩展 → Quick Look”，启用 SpaceLens，然后重新打开 Quick Look。

也可以使用 Xcode 打开 `SpaceLens.xcodeproj`，选择 `SpaceLens` scheme 后构建。签名设置保持 `Sign to Run Locally` 即可。

## 更新

拉取最新代码，退出 SpaceLens 并关闭所有 Quick Look 窗口，然后运行：

```sh
git pull --ff-only
./scripts/build.sh
./scripts/install.sh --replace
```

安装脚本会先核对现有应用的 bundle identifier，避免覆盖其他应用。旧版本会临时保留在脚本输出的位置；更新失败时可以手动恢复。

## 卸载

退出 SpaceLens 并关闭 Quick Look 窗口，然后运行：

```sh
./scripts/uninstall.sh --remove
```

脚本会注销 Quick Look 扩展并把应用移入废纸篓，不会删除源码或用户文件。

## 预览的启用与停用

SpaceLens 只在你打开应用时提供预览：退出 SpaceLens（⌘Q 或菜单栏“退出 SpaceLens”）会**停用预览扩展**，空格预览随即回到 macOS 原生行为；重新打开 SpaceLens 会自动恢复。因此**重启 Mac 后需要先打开一次 SpaceLens**，它的预览才会生效。

手动选择同样有效，并且会被保留——如果你在系统设置里停用了扩展，SpaceLens 下次启动不会覆盖它：

- 系统设置 → 通用 → 登录项与扩展 → Quick Look，关闭或打开 SpaceLens。
- 或在终端停用 `pluginkit -e ignore -i io.github.linzh0632.SpaceLens.Preview`，恢复 `pluginkit -e use -i io.github.linzh0632.SpaceLens.Preview`。

强制退出（活动监视器“强制结束”、崩溃或断电）时停用步骤不会执行，扩展会保持启用，直到下一次正常退出。应用设置界面会显示扩展当前是启用还是停用。

如果不想每次开机后手动打开应用，可以在**通用设置**里开启“开机自启动”（需要 macOS 13 或更高版本）：登录 Mac 后 SpaceLens 会自动启动，预览随之可用。

## 设置与网络

设置界面分为“功能设置 / 通用设置 / 关于”三页，可以查看扩展状态、预览范围、开关菜单栏图标与开机自启动，并检查更新。界面语言可在“通用设置 → 语言”中切换为简体中文或英文：设置界面立即生效，已打开的预览窗口保持原语言，重新打开后使用新语言。

检查更新是 SpaceLens 唯一的网络行为，默认关闭：开启后会在启动时向 GitHub Releases 查询最新版本号，只用于版本比较，不附带文件、文件名、目录结构或使用数据。GitHub 仍会像处理普通网络请求一样接收到建立连接所需的信息，例如 IP 地址。

## 故障排查

### 按空格没有出现 SpaceLens

- 确认 SpaceLens 已在系统设置的 Quick Look 扩展列表中启用。
- 关闭当前 Quick Look 窗口后重新打开。
- 若同一格式安装了多个预览扩展，macOS 会自行选择处理器；可暂时关闭冲突扩展后重试。
- 图片、PDF、音视频、CSV 和普通 TXT 可能继续由 macOS 原生预览处理，这是预期行为。

### 更新后仍显示旧界面

先退出 SpaceLens、关闭 Quick Look，再重新执行构建和覆盖安装。必要时注销当前账号或重启 Mac，让系统刷新扩展缓存。

### 手动注销扩展

移动应用前可以运行：

```sh
pluginkit -r /Applications/SpaceLens.app/Contents/PlugIns/SpaceLensPreview.appex
```

## 构建说明

构建产物默认放在系统临时目录，避免同步文件夹附加的 Finder 元数据影响签名。高级用户可以使用 `SPACELENS_DERIVED_DATA` 和 `SPACELENS_TEST_BUILD` 修改位置；构建与安装必须使用相同的 `SPACELENS_DERIVED_DATA`。
