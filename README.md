# SpaceLens

按下空格，多看一点。

SpaceLens 是一个开源的 macOS Quick Look 扩展，用来直接预览文件夹、压缩包、代码、结构化数据和常见开发文件。所有解析和渲染都在本机完成；它只负责预览，不会接管文件的双击打开方式。

[![macOS release check](https://github.com/linzh0632/SpaceLens/actions/workflows/macos.yml/badge.svg?branch=main)](https://github.com/linzh0632/SpaceLens/actions/workflows/macos.yml)

## 主要功能

- 文件夹和归档以可展开的树形列表显示名称、类型、大小和修改时间。
- 点击文件夹或 ZIP 中的文件，可在右侧窗格继续预览内容。
- 支持 Markdown、代码、配置、JSON、JSON Lines、TSV、plist、SQLite 和 Jupyter Notebook。
- 支持 TAR、GZ、TGZ、BZ2、TBZ2、XZ、TXZ 等常见归档格式。
- 支持 Mermaid、PlantUML、Draw.io、Parquet、Arrow、Feather 和 Avro。
- 界面提供简体中文与英文两种语言，可在“通用设置 → 语言”中切换；预览窗口使用同一语言。
- 日期和明暗外观跟随 macOS 设置。
- 设置界面按“功能设置 / 通用设置 / 关于”分区，集中显示扩展状态与预览范围，并提供菜单栏图标、开机自启动与检查更新。
- 无账号、无遥测、不上传文件；唯一的网络请求是检查更新时向 GitHub 查询版本号，默认关闭，可在通用设置中开启。不执行预览文件中的代码。

完整格式与限制见[支持格式](docs/FEATURE-MATRIX.md)。

## 系统要求

- macOS 12 或更高版本
- 完整版 Xcode 及 Command Line Tools（从源码构建时需要）

目前已在 Apple Silicon 和 macOS 27 上完成实机验收。项目会构建 arm64 与 x86_64 通用应用，但 Intel Mac 和较早 macOS 版本尚未完成实机测试。

## 安装

SpaceLens 目前提供源码安装，尚未发布经过 Apple Developer ID 签名和公证的安装包。

```sh
git clone https://github.com/linzh0632/SpaceLens.git
cd SpaceLens
./scripts/build.sh
./scripts/install.sh
```

默认安装到 `/Applications/SpaceLens.app`。首次使用时，如 Finder 没有调用 SpaceLens，请在“系统设置 → 通用 → 登录项与扩展 → Quick Look”中启用它。

详细的更新、卸载和故障排查步骤见[安装指南](docs/INSTALL.md)。

## 使用

1. 在 Finder 中选中文件、文件夹或归档。
2. 按空格打开 Quick Look。
3. 在文件夹或归档列表中选择文件，即可在右侧窗格继续预览；点击“关闭”可收起右侧窗格。

SpaceLens 只在运行时提供预览：退出应用会停用预览扩展，空格预览回到 macOS 原生行为，重新打开应用后自动恢复。因此重启 Mac 后需要先打开一次 SpaceLens；在通用设置中开启“开机自启动”后，登录时它会自动启动，预览随之可用。

SpaceLens 不注册为文档打开程序。双击文件仍由系统或你选择的编辑器处理。图片、PDF、音频和视频等 macOS 已经支持的格式继续使用系统原生 Quick Look；在 macOS 27 上，CSV 与普通 TXT 也可能优先使用系统预览。

## 隐私与安全

SpaceLens 只读取你在 Finder 中选择预览的内容，不上传文件，不收集使用数据，也不加载远程资源。唯一的网络请求是检查更新时向 GitHub 查询版本号，默认关闭，可在通用设置中开启。详细说明见[隐私说明](docs/PRIVACY.md)和[安全策略](SECURITY.md)。

## 参与开发

欢迎提交问题和改进。开始前请阅读[贡献指南](CONTRIBUTING.md)。项目的自动检查、构建边界和维护流程见[维护说明](docs/MAINTENANCE.md)。

## 许可证

SpaceLens 使用 [MIT License](LICENSE)。
