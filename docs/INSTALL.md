# 安装 SpaceLens

SpaceLens 当前版本为 **0.5.3（构建 16）**。目前没有已签名、公证的二进制安装包，需要使用完整 Xcode 从源码构建。

## 准备环境

1. 安装 Xcode。
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
