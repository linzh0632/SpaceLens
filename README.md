# SpaceLens

**按下空格，多看一点。**

[English](README.en.md) · 简体中文

[![macOS release check](https://github.com/linzh0632/SpaceLens/actions/workflows/macos.yml/badge.svg?branch=main)](https://github.com/linzh0632/SpaceLens/actions/workflows/macos.yml)

SpaceLens 是一个开源的 macOS Quick Look 扩展。它让 Finder 可以直接预览文件夹、压缩包、代码、结构化数据和常见开发文件，同时保留 macOS 原生 Quick Look 的使用方式：选中文件，按下空格即可。

所有文件解析和渲染都在本机完成。SpaceLens 只负责预览，不编辑文件，也不会成为文件的默认打开应用。

## 项目缘起

SpaceLens 是我的第一个开源项目。它源于一次很普通的经历：把论文打包发给老师之前，我想先确认压缩包里的文件是否完整，却发现 macOS 原生 Quick Look 只能显示压缩包的基本信息，无法直接浏览其中的内容。搜索之后，我发现能够实现类似功能的应用大多需要付费，于是决定在 AI 的协助下自己动手开发，最终有了 SpaceLens。

SpaceLens 从压缩包预览起步，如今也能预览文件夹、代码、文档、结构化数据和多种常见开发文件。它延续了 macOS 熟悉的操作方式：在 Finder 中选中内容，按下空格即可查看；文件始终留在本机，SpaceLens 也不会取代原有的默认打开应用。

希望它能为有相同需求的人带来一些便利。也欢迎通过 Issue 和 Pull Request 一起完善这个项目。

## 为什么使用 SpaceLens

- **浏览文件夹和归档**：以可展开的树形列表查看名称、类型、大小和修改时间。
- **就地查看文件内容**：在列表中选择文件，右侧窗格继续显示图片、文本、代码、表格或结构化内容。
- **覆盖开发常用格式**：支持 Markdown、代码与配置、JSON、plist、SQLite、Notebook、图表和列式数据。
- **保留系统原生体验**：图片、PDF、音视频等格式继续使用 macOS 原生 Quick Look。
- **本地、只读、可控**：无账号、无遥测、不上传文件、不执行预览内容；更新检查默认关闭。

## 支持范围

| 类别 | 代表格式 |
|---|---|
| 文件夹与归档 | 文件夹、ZIP、TAR、GZ、TGZ、BZ2、TBZ2、XZ、TXZ |
| 文本与代码 | Markdown、常见源代码、配置、日志、diff、SQL、GraphQL、UTF-8/UTF-16 文本 |
| 结构化数据 | JSON、JSON Lines、TSV、XML/Binary/OpenStep plist、SQLite |
| 技术文档 | Jupyter Notebook、MDX、Quarto、R Markdown、reStructuredText、AsciiDoc、TeX |
| 图表 | Mermaid、PlantUML、Draw.io |
| 数据工程 | Parquet、Arrow IPC、Feather v2、Avro OCF |
| 文件夹内表格 | `.xlsx`、`.xlsm`，支持工作表切换 |

不同格式的读取上限、容器内预览能力和已知限制见[支持格式与限制](docs/FEATURE-MATRIX.md)。

## 系统要求

- **运行构建后的应用**：macOS 12 或更高版本。
- **从当前源码构建**：macOS 15.6 或更高版本、Xcode 26 或更高版本。新版应用图标使用 Xcode 26 引入的 Icon Composer 格式。

项目会生成 arm64 与 x86_64 通用应用。目前已在 Apple Silicon、macOS 27 上完成实机验收；Intel Mac 和 macOS 12–26 尚未完成实机测试。由于当前只提供源码安装，实际构建机器需要满足上面的 Xcode 要求。

## 安装

SpaceLens 目前提供源码安装，尚未发布经过 Apple Developer ID 签名和公证的安装包。

```sh
git clone https://github.com/linzh0632/SpaceLens.git
cd SpaceLens
./scripts/build.sh
./scripts/install.sh
```

应用默认安装到 `/Applications/SpaceLens.app`。首次启动后，如果 Finder 仍使用系统信息面板，请前往“系统设置 → 通用 → 登录项与扩展 → Quick Look”并启用 SpaceLens。

更新、卸载和故障排查步骤见[安装指南](docs/INSTALL.md)。

## 使用

1. 打开 SpaceLens，让预览扩展在本次会话中生效。
2. 在 Finder 中选中文件、文件夹或归档并按空格。
3. 在文件夹或归档列表中选择文件，可在右侧继续预览；点击“关闭”收起右侧窗格。

SpaceLens 只在应用运行时提供预览。正常退出 SpaceLens 会停用扩展，让空格预览回到 macOS 原生行为；重新打开应用会自动恢复。若希望每次登录后立即可用，可在“通用设置”中开启“开机自启动”（macOS 13 或更高版本）。

## 需要了解的边界

- SpaceLens 不注册文档打开角色。双击文件仍由原有默认应用处理。
- macOS 会在多个 Quick Look 扩展之间选择处理器，因此 CSV、普通 TXT 或其他已有系统预览的格式可能不会交给 SpaceLens。
- `.xlsx` / `.xlsm` 仅支持在**文件夹右侧窗格**中预览；直接按空格仍由系统或 Excel 处理，压缩包内的 Excel 文件暂不支持。
- 公式只显示工作簿中保存的缓存值，SpaceLens 不计算公式，也不读取或运行宏。

## 隐私与安全

SpaceLens 不上传文件、文件名、目录结构或预览结果，不加载文档中的远程资源，也不执行源代码、脚本、Notebook 单元格或文档宏。唯一的网络功能是可选的更新检查：启用后向 GitHub 查询最新版本号，默认关闭。

详见[隐私说明](docs/PRIVACY.md)、[安全策略](SECURITY.md)和[文件关联说明](docs/FILE-ASSOCIATIONS.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [安装指南](docs/INSTALL.md) | 构建、安装、更新、卸载与故障排查 |
| [支持格式与限制](docs/FEATURE-MATRIX.md) | 完整格式范围、安全上限与容器预览限制 |
| [隐私说明](docs/PRIVACY.md) | 本地处理、网络行为和偏好设置 |
| [贡献指南](CONTRIBUTING.md) | 开发环境、测试和 Pull Request 要求 |
| [维护说明](docs/MAINTENANCE.md) | 版本更新与发布检查 |
| [更新记录](CHANGELOG.md) | 各版本变化 |

更多资料及历史开发记录见[文档索引](docs/README.md)。

## 参与项目

欢迎提交 Issue 和 Pull Request。报告兼容性问题时，请避免上传包含隐私信息的真实文件，并尽量提供最小的合成样例。参与前请阅读[贡献指南](CONTRIBUTING.md)和[行为准则](CODE_OF_CONDUCT.md)。

## 许可证

SpaceLens 使用 [MIT License](LICENSE)。
