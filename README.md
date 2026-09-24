# SpaceLens · 空格镜

按下空格，多看一点。

面向 macOS 的本地快速预览增强工具，保留系统原生预览体验，并以 Super Quick Look 的公开功能为首版对照目标。

**当前状态：M1 至 M6 已完成并通过自动检查与 Finder 实机验收。文件夹和归档列表支持按系统语言显示修改时间。已实现文件夹、常用归档、文本、代码、配置、Markdown、CSV/TSV、JSON、plist、SQLite、扩展文档、Jupyter Notebook，以及 Mermaid、PlantUML、Draw.io、Parquet、Arrow、Feather 和 Avro 的本地预览。macOS 27 对 CSV 与普通 TXT 固定优先使用系统预览，SpaceLens 保留该原生行为。**

- [安装、更新与卸载](docs/INSTALL.md)
- [M1 实测结果与限制](docs/M1-RESULTS.md)
- [M2 范围与验收](docs/M2-RESULTS.md)
- [M3 范围与验收](docs/M3-RESULTS.md)
- [M4A 范围与验收](docs/M4A-RESULTS.md)
- [M4B 范围与验收](docs/M4B-RESULTS.md)
- [M4C 范围与验收](docs/M4C-RESULTS.md)
- [M4D 范围与验收](docs/M4D-RESULTS.md)
- [M4E 范围与验收](docs/M4E-RESULTS.md)
- [M4F 范围与验收](docs/M4F-RESULTS.md)
- [M5 范围与验收](docs/M5-RESULTS.md)
- [M6 范围与验收](docs/M6-RESULTS.md)
- [维护说明](docs/MAINTENANCE.md)
- [文件类型与默认打开应用审计](docs/FILE-ASSOCIATIONS.md)

- [开发前检查与实施计划](docs/DEVELOPMENT-READINESS.md)
- [功能对照与验收矩阵](docs/FEATURE-MATRIX.md)
- [项目目标与约定](SpaceLens-PREPARATION.md)

## 开发环境

本机已安装 Xcode 27.0 与 macOS 27 SDK。Swift 编译运行、基础本地签名及 GitHub 连接验证均已通过；Finder 的验收文件与文件夹接入已由用户实测确认。macOS 12 为候选最低版本，尚未验证兼容性。

## 协作

GitHub： https://github.com/linzh0632/SpaceLens

使用功能分支开发，每个大功能完成并验证后推送。当前按私有仓库管理，成熟后再由用户决定公开；许可证待公开前确定。
