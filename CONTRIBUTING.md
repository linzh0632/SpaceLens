# Contributing to SpaceLens

欢迎提交问题、格式兼容性样例和代码改进。SpaceLens 的首要原则是：预览必须保持本地、只读，并且不能改变文件的默认打开方式。

## 提交问题

请说明 macOS 版本、SpaceLens 版本、文件格式、预期结果、实际结果和稳定的复现步骤。不要公开上传包含隐私信息的真实文件；尽量提供可复现问题的最小合成样例。安全问题请按 [SECURITY.md](SECURITY.md) 中的方式报告。

## 本地开发

需要完整 Xcode。克隆仓库后运行：

```sh
./scripts/test.sh
./scripts/build.sh
```

提交前运行完整发布检查：

```sh
./scripts/release-check.sh
```

该命令会执行核心测试、元数据检查、Release 构建、签名检查，并确认 arm64/x86_64 通用二进制。

## 代码原则

- 预览必须保持只读、本地处理，不执行文件中的代码或加载远程资源。
- 不把 SpaceLens 注册为普通文件的默认打开应用。
- 为新的解析边界、损坏输入和读取上限补充有意义的测试。
- 测试样例放在项目内 `build/fixtures/<功能>`，完成后及时删除，不提交个人数据或生成产物。
- 用户可见行为变化需要同步更新 README 或 `docs/`。

提交 Pull Request 时，请简要说明触发场景、行为变化和验证方式。

## Pull Request 检查清单

- 改动范围清晰，没有无关的格式化或生成文件。
- 新增解析逻辑包含损坏输入、读取上限和取消操作等必要测试。
- 用户可见行为、支持格式或隐私边界发生变化时，相关文档已经同步更新。
- `./scripts/release-check.sh` 已通过。

---

## English

Issues, compatibility reports, and pull requests are welcome. SpaceLens previews must remain local and read-only, and the host app must never become a default document opener.

When reporting a bug, include the macOS and SpaceLens versions, file format, expected and observed behavior, and reliable reproduction steps. Do not attach private files to public issues; prefer a minimal synthetic fixture. Report security issues as described in [SECURITY.md](SECURITY.md).

Development requires full Xcode. Before opening a pull request, run:

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/release-check.sh
```

Keep previews local, avoid executing or remotely loading document content, preserve strict read limits, and add meaningful tests for malformed input. Update user documentation whenever supported formats, privacy behavior, installation, or visible behavior changes.
