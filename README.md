# SpaceLens · 空格镜

按下空格，多看一点。

面向 macOS 的本地快速预览增强工具，保留系统原生预览体验，并以 Super Quick Look 的公开功能为首版对照目标。

**当前状态：M2 开发中；已实现递归文件夹树和 ZIP 只读内容预览。**

- [安装、更新与卸载](docs/INSTALL.md)
- [M1 实测结果与限制](docs/M1-RESULTS.md)
- [M2 范围与验收](docs/M2-RESULTS.md)

- [开发前检查与实施计划](docs/DEVELOPMENT-READINESS.md)
- [功能对照与验收矩阵](docs/FEATURE-MATRIX.md)
- [项目目标与约定](SpaceLens-PREPARATION.md)

## 开发环境

本机已安装 Xcode 27.0 与 macOS 27 SDK。Swift 编译运行、基础本地签名及 GitHub 连接验证均已通过；Finder 的验收文件与文件夹接入已由用户实测确认。macOS 12 为候选最低版本，尚未验证兼容性。

## 协作

GitHub： https://github.com/linzh0632/SpaceLens

使用功能分支开发，每个大功能完成并验证后推送。当前按私有仓库管理，成熟后再由用户决定公开；许可证待公开前确定。
