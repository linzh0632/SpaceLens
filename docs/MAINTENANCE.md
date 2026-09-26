# SpaceLens 维护说明

## 日常检查

功能改动完成后运行 `./scripts/release-check.sh`。它会从独立临时目录运行核心测试，检查两个 Info.plist 的版本一致性、Quick Look 扩展声明、主应用没有文档打开角色、Release 签名，以及 arm64/x86_64 通用二进制。GitHub Actions 对 `main` 和 Pull Request 运行相同命令。

## 版本更新

每个候选版本同时更新 `Config/App-Info.plist` 与 `Config/Preview-Info.plist` 中的短版本和构建号，构建号必须递增。同步更新 `CHANGELOG.md` 和用户文档。覆盖安装前退出 SpaceLens 和 Quick Look 窗口，然后运行 `./scripts/build.sh` 和 `./scripts/install.sh --replace`。

## 安全卸载

退出 SpaceLens 和 Quick Look 窗口后运行 `./scripts/uninstall.sh --remove`。脚本只处理 bundle identifier 为 `io.github.linzh0632.SpaceLens` 的应用，将其移入废纸篓，并注销随附的 Quick Look 扩展。源码仓库和用户文件不会被修改。

## 发布边界

- 当前应用使用本机 ad hoc 签名，适合源码构建；尚未使用 Developer ID 签名或 Apple 公证。
- 当前仅在 Apple Silicon、macOS 27 上完成 Finder 实机验收。工程最低目标为 macOS 12，并会构建通用二进制，但 Intel 与较早 macOS 尚无实机验收。
- 阶段样例只存放在 `build/fixtures/<阶段>`，验收后立即删除，不提交生成文件或个人数据。
- 公开版本使用 MIT License；第三方贡献必须能够按相同许可证发布。
