# SpaceLens 开发前检查

检查日期：2026-09-23。状态：基础开发环境检查通过，可以开始 M1。宿主应用与预览扩展的实机验收尚未进行。

## 环境结果

| 项目 | 结果 |
|---|---|
| 主机 | Apple Silicon arm64，macOS 27.0（26A428） |
| Xcode | 27.0（27A266a），/Applications/Xcode.app |
| 当前开发目录 | /Applications/Xcode.app/Contents/Developer |
| macOS SDK | Xcode 内已存在 macOS 27 SDK |
| 扩展模板 | 已存在 macOS Quick Look Preview Extension 模板 |
| 磁盘可用空间 | 约 767 GiB |
| 基础工具 | Swift 6.4、xcodebuild、Git、codesign、pluginkit 已运行；其余工具路径已确认 |
| 签名身份 | 0 个有效代码签名身份；拟先验证本地 ad hoc 签名 |
| Xcode 许可 | 初检受阻；随后复查 Swift/Git 正常，首次启动状态检查返回成功 |
| 扩展枚举 | 受限环境初检失败；提升执行权限后枚举成功。已存在 Looq、Draw.io 等第三方预览扩展 |
| Git | origin 已配置为 https://github.com/linzh0632/SpaceLens.git；main 跟踪 origin/main |
| 提交 | 本次联网读取远程 main，确认与本地初始提交 b05d350 一致；本报告随后另行提交推送 |

## 基础验证记录

1. Xcode 首次启动状态检查成功；Swift 6.4、macOS SDK 27.0 可用。
2. 临时 Swift 样例成功导入 Foundation、AppKit、SwiftUI、QuickLookUI、WebKit、UniformTypeIdentifiers，编译及运行通过。
3. 二进制 ad hoc 签名成功，严格签名校验通过，签名后再次运行成功。这不代表宿主/扩展权限与加载验证已经完成。
4. 远程 main 读取成功，文档修改前无用户未提交改动。GitHub 连接器返回空仓库列表，无法独立核实可见性；继续按用户指定私有仓库处理，不改变可见性。
5. 本机已有 Looq 的 folders、markdown、code、data、packages 预览扩展，以及 Draw.io 扩展。M1 必须确认实际命中的处理器，不能把其他扩展输出当成 SpaceLens 的成功结果；不自动禁用已有扩展。

不需要提前安装 Node、Python 包、CocoaPods、Homebrew、XcodeGen 或其他平台模拟器。首阶段优先用 Xcode 原生工程、Swift 和系统框架；新增第三方依赖先核查用途、许可证、体积、离线能力与最低系统要求。

## 技术决策

- 宿主：Swift + SwiftUI/AppKit。预览扩展：QuickLookUI + NSViewController/QLPreviewingController。
- 核心解析与模型独立于界面，便于单元测试。HTML 内容按需要由受限 WKWebView 展示。
- 系统支持的图片、PDF、音视频等继续使用原生 Quick Look；不抢占宽泛文件类型。
- 首个验证环境为本机 arm64/macOS 27。macOS 12 仅为候选兼容目标；未测试前不声明支持，Intel 同理。
- 本地自用优先验证不依赖付费证书的构建。是否能满足宿主/扩展加载与权限要求由 M1 决定。
- 不引入长期后台进程或全局按键监听，除非标准方案验证失败并重新评估。

## 开发顺序与通过条件

| 阶段 | 交付物 | 通过条件 |
|---|---|---|
| M0 准备 | 环境报告、范围表、Git 约定 | 许可完成，基础编译运行和本地签名通过，远程同步正常 |
| M1 接入验证 | 最小宿主、预览扩展、安装/卸载说明 | Finder 实际按空格加载自定义样例；文件夹权限和接入路径明确；重启、更新可恢复；原生图片/PDF/音视频不受影响 |
| M2 文件夹与 ZIP | 文件树、元数据与受限归档枚举 | 正常、空、损坏、加密、超大、无权限样例行为清楚；取消有效；符号链接不导致循环 |
| M3 常用格式 | 文本/代码/配置/Markdown/CSV/JSON | 每类代表样例和编码异常通过；离线渲染；输出不执行嵌入代码 |
| M4 全范围补齐 | 其他文档、图表、归档、数据库 | 按功能矩阵逐项验证，不将文本回退标为完整渲染 |
| M5 日常使用 | 本机安装包、回归记录、维护说明 | 连续使用、睡眠唤醒、升级覆盖与卸载验证；无残留权限需求；明确支持边界 |

M1 若发现标准扩展不支持预期文件夹体验，应先记录实验和替代方案，再确定架构，避免在接入未验证前扩充全部格式。

## 验证与性能

核心解析写有意义的单元测试，扩展加载和 Finder 交互做实机验收；实际工程存在后再添加 macOS CI。

初始工程预算（待实测调整）：普通小文件首次预览目标 1 秒内；目录/归档默认最多 10,000 条目、深度 10；文本输入预算 5 MiB；数据库只读且每表最多展示 100 行。达到限制时展示截断原因，并支持取消。预算是 SpaceLens 的初始设计值，不是竞品保证或已测结果。

回归样例包括：空内容、中文与非 UTF-8、超长文件名、损坏文件、深层目录、符号链接循环、云端占位文件、外部磁盘、权限拒绝、HTML 注入、归档路径越界和压缩炸弹。仅用合成样例。

## Git 与交付

main 保持已验证状态；后续功能使用 feat/* 分支。大功能通过相关验证后提交并推送；不强制推送、不提交证书和用户数据。私有仓库成熟后是否公开由用户决定，公开前选择许可证。文档和计划不代表功能已完成。

## 来源

- https://superquicklook.lumik.space/
- https://developer.apple.com/documentation/quicklookui/
