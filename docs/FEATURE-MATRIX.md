# SpaceLens 功能对照与验收矩阵

依据 Super Quick Look 官网公开范围（2026-09-23）。M1 已实现专用验收文件和文件夹浅层预览，其余增强功能未实现；公开演示不等于已购买并逐项测试。相同效果以样例验收为准，不复制竞品实现或资源。

| 范围 | 目标 | 验收重点 |
|---|---|---|
| Finder | 空格打开预览，原生操作共存 | 实机文件切换、关闭、重启、扩展启停 |
| 原生格式 | 保留图片、PDF、音视频等系统支持 | 安装前后对照，不抢占通用 UTI |
| 文件夹 | 层级、数量、深度、修改时间、类型、大小、图标 | M2 已实现可展开树、数量、深度、时间、类型、文件大小、图标和限制 |
| 归档 | ZIP、TAR、GZ、TGZ、BZ2、TBZ2、XZ、TXZ | M2 已实现 ZIP；M4A 已实现其他列出格式的只读条目、元数据、损坏文件、危险路径和数量上限，Finder 视觉验收已通过 |
| 文档 | Markdown、MDX、IPYNB、QMD、RMD、RST、AsciiDoc、TeX | M3 已实现基础 Markdown；M4C 已实现 MDX/QMD/RMD 排版、RST/AsciiDoc/TeX 结构转换，以及 IPYNB 单元格与已有文本输出预览，Finder 视觉验收已通过 |
| 图表 | Draw.io、Mermaid/MMD、PlantUML/PUML | M4D 已实现 Mermaid flowchart/graph/sequenceDiagram、PlantUML 基础关系/sequence，以及压缩和未压缩 Draw.io XML 的本地 SVG 预览；无网络、无外部进程，错误与限制明确显示 |
| 代码与配置 | 官网展示的源代码、配置、diff、log、SQL、GraphQL 和特殊文件名 | M3 已实现通用本地语法着色、UTF-8/UTF-16 与 5 MiB 上限；无扩展名特殊文件仍需实机逐项注册 |
| 文本数据 | CSV、TSV、JSON、JSONL、NDJSON、plist | M3 已实现 CSV/TSV 表格和 JSON/JSON Lines 结构树；M4B 已实现 XML、Binary 与 OpenStep plist 结构树、错误提示和读取上限，Finder 视觉验收已通过 |
| 数据库 | DB、SQLite、SQLite3 | M4B 已实现用户表、列定义、数据类型、NULL/BLOB 显示和每表最多 100 行只读样本，Finder 视觉验收已通过 |
| 列式及其他数据 | Parquet、Arrow、Feather、Avro | schema、元信息、限量数据；依赖与格式版本边界 |
| 本地处理 | 无文件上传、无账号要求 | 断网验收；渲染不请求远程资源 |

官网“106 formats represented”是展示统计，包含样例与别名，不直接用作独立格式验收数量。实施前将公开样例整理为文件级清单，每项记录处理器、支持程度、测试样例和限制。
