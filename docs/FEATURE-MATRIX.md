# SpaceLens 功能对照与验收矩阵

依据 Super Quick Look 官网公开范围（2026-09-23）。M1 至 M6 已完成，M7a 已实现容器内条目预览，下表逐项记录实际验收状态；公开演示不等于已购买并逐项测试。相同效果以样例验收为准，不复制竞品实现或资源。

| 范围 | 目标 | 验收重点 |
|---|---|---|
| 容器内条目 | 点击文件夹/归档中的条目就地预览 | M7a 已实现右侧窗格；文件夹来源复用全部既有类型，归档来源在内存抽取（图片、文本、代码、文档、表格、结构化、图表）；归档内需要文件路径的类型与嵌套容器明确不支持，见 [M7a 验收](M7-RESULTS.md) |
| Finder | 空格打开预览，原生操作共存 | 实机文件切换、关闭、重启、扩展启停 |
| 原生格式 | 保留图片、PDF、音视频等系统支持 | 安装前后对照，不抢占通用 UTI |
| 文件夹 | 层级、数量、深度、修改时间、类型、大小、图标 | M2 已实现可展开树、数量、深度、时间、类型、文件大小、图标和限制 |
| 归档 | ZIP、TAR、GZ、TGZ、BZ2、TBZ2、XZ、TXZ | M2 已实现 ZIP；M4A 已实现其他列出格式的只读条目、元数据、损坏文件、危险路径和数量上限，Finder 视觉验收已通过 |
| 文档 | Markdown、MDX、IPYNB、QMD、RMD、RST、AsciiDoc、TeX | M3 已实现基础 Markdown；M4C 已实现 MDX/QMD/RMD 排版、RST/AsciiDoc/TeX 结构转换，以及 IPYNB 单元格与已有文本输出预览，Finder 视觉验收已通过 |
| 图表 | Draw.io、Mermaid/MMD、PlantUML/PUML | M4D 已实现 Mermaid flowchart/graph/sequenceDiagram、PlantUML 基础关系/sequence，以及压缩和未压缩 Draw.io XML 的本地 SVG 预览；无网络、无外部进程，错误与限制明确显示 |
| 代码与配置 | 官网展示的源代码、配置、diff、log、SQL、GraphQL 和特殊文件名 | M4F 核心加载器已覆盖官网 72 个代码与配置样例；新增 49 个安全扩展名、常见标准 UTI 与 Makefile 路由，保留 UTF-8/UTF-16、5 MiB 和 1,000 行限制；Finder 视觉验收已通过 |
| 文本数据 | CSV、TSV、JSON、JSONL、NDJSON、plist | M3 已实现 CSV/TSV 表格和 JSON/JSON Lines 结构树；M4B 已实现 XML、Binary 与 OpenStep plist 结构树、错误提示和读取上限，Finder 视觉验收已通过 |
| 数据库 | DB、SQLite、SQLite3 | M4B 已实现用户表、列定义、数据类型、NULL/BLOB 显示和每表最多 100 行只读样本，Finder 视觉验收已通过 |
| 列式及其他数据 | Parquet、Arrow、Feather、Avro | M4E 已实现 Parquet schema/文件元信息、Arrow IPC/Feather v2 与 Avro OCF 前 100 行预览；复杂或压缩 Arrow 列安全回退到 schema，格式边界与错误明确显示；Finder 视觉验收已通过 |
| 本地处理 | 无文件上传、无账号要求 | 断网验收；渲染不请求远程资源 |

官网“106 formats represented”是展示统计，包含样例与别名，不直接用作独立格式验收数量。实施前将公开样例整理为文件级清单，每项记录处理器、支持程度、测试样例和限制。
