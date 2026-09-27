# Security Policy

## Supported versions

Security fixes are applied to the latest code on `main`. Older source snapshots and locally built applications may no longer receive fixes.

SpaceLens currently publishes source code rather than a Developer ID-signed and notarized binary. Verify that you cloned this repository and review the installation steps before building.

## Reporting a vulnerability

Please do not attach private or sensitive sample files to a public issue. Use GitHub's private vulnerability reporting for this repository when available. Otherwise, open an issue containing only a minimal, non-sensitive description and ask the maintainer for a private channel.

A useful report includes the affected SpaceLens version, macOS version, file format, expected behavior, observed behavior, and a minimal synthetic sample when one can be shared safely.

## Scope

Security-sensitive areas include malformed-file handling, archive path traversal, resource-exhaustion limits, sandbox or file-access boundaries, unintended network access, execution of previewed content, and accidental document-opening associations.

Please report ordinary rendering errors and format-compatibility problems through a regular issue when the sample is safe to share.

---

## 中文说明

安全修复以 `main` 分支的最新代码为准。请不要在公开 Issue 中上传含有隐私或敏感信息的真实样例；优先使用 GitHub 的私密漏洞报告功能。报告中请包含 SpaceLens 与 macOS 版本、文件格式、复现步骤、预期结果和实际结果，并尽可能使用最小合成样例。
