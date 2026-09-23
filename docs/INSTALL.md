# SpaceLens 本机安装与验收

当前为 M2（0.2.0），支持专用 `.spacelens` 文件、递归文件夹树与 ZIP 只读内容预览。代码高亮等属于后续阶段。

## 构建与安装

需要完整 Xcode，首次启动已完成。在项目根目录执行：

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/install.sh
```

默认安装到 `/Applications/SpaceLens.app`。如系统要求目录写入许可，允许本次安装即可。脚本使用本地 ad hoc 签名，不需要付费证书。**这个安装方式仅在本机验证过，不是经过 Apple 公证的分发包。**

构建和测试产物默认放在系统临时目录，以避免同步文件夹附加的 Finder 元数据破坏签名。可设置 `SPACELENS_DERIVED_DATA` 和 `SPACELENS_TEST_BUILD` 指向其他非同步本地目录；安装时要使用与构建时相同的 `SPACELENS_DERIVED_DATA`。

也可以用 Xcode 打开 `SpaceLens.xcodeproj`，选 SpaceLens scheme，签名保持 Sign to Run Locally。首次构建时让 Derived Data 保持默认本机位置。

## 使用

1. 打开 SpaceLens，点击“创建验收文件…”保存 Hello.spacelens。
2. 在 Finder 选中文件按空格，应出现“SpaceLens · 验收文件”。
3. 选择普通文件夹按空格，应出现“SpaceLens · 文件夹”，最多读取 10,000 项和 10 层。
4. 选择 ZIP 按空格，应显示归档条目、大小、压缩方法和修改时间；SpaceLens 不会解压内容。
5. 若没有出现，打开系统设置，查找“登录项与扩展”中的 Quick Look，启用 SpaceLens。不同系统版本的入口可能不同。

本机已有 Looq。若同类文件被它接管，需要在系统设置中选择预览扩展。SpaceLens 不会自动关闭其他应用的扩展，也不会注册图片、PDF、音视频等通用类型。

## 更新

先退出 SpaceLens、关闭它的预览窗口，然后：

```sh
./scripts/build.sh
./scripts/install.sh --replace
```

安装脚本检查原应用身份，并将旧版保留在输出所示的临时备份目录。若更新失败，可将其中 `SpaceLens.previous` 恢复为 `/Applications/SpaceLens.app`。旧备份会随系统临时目录清理消失；它不替代 Git 版本控制。

## 卸载与撤销

退出 SpaceLens、关闭预览窗口；在系统设置的 Quick Look 扩展中关闭 SpaceLens，将 `/Applications/SpaceLens.app` 移到废纸篓。不要删除或禁用 Looq 等其他应用。已保存的验收文件可自行保留或删除，源码仓库不受影响。

如果系统仍显示旧注册项，可运行：

```sh
pluginkit -r /Applications/SpaceLens.app/Contents/PlugIns/SpaceLensPreview.appex
```

此命令应在移动应用前执行。Finder 的短时缓存不代表应用仍然安装；关闭后重新打开预览再检查，必要时重新登录。

## 验收清单

- [x] 本机 `.spacelens` 预览显示 SpaceLens 标识（用户确认）
- [x] 本机文件夹预览显示 SpaceLens 标识（用户确认）
- [x] 应用退出后覆盖安装、再次启动、已启用的扩展注册保留
- [x] 更新后 Finder 再次预览（用户确认正常）
- [x] 原生 PNG/PDF/WAV/MOV 预览（用户确认全部正常）
- [ ] 整机重启后再预览（未重启用户电脑）
- [ ] 其他 macOS 版本及 Intel 实机（尚未验证）

原生图片/PDF/音频/视频样例可用 `xcrun swift scripts/create-native-fixtures.swift build/NativeFixtures` 生成。视频生成器使用兼容旧 SDK 的 API，在 macOS 27 上会给出弃用警告，不影响产品代码。生成文件不进入仓库。
