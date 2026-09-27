# M4E 列式及其他数据预览

状态：已完成；44 项自动测试、通用 Release 构建、本机扩展调用和 Finder 视觉验收均通过。

## 实现范围

- Parquet：读取文件尾 Thrift Compact 元数据，显示总行数、行组、创建器、自定义元信息，以及字段路径、物理类型、逻辑类型和重复规则。
- Arrow IPC 与 Feather v2：读取 FlatBuffer schema、record batch 和基础数据 buffer，显示字段及前 100 行。支持整数、浮点、布尔、UTF-8、Binary、日期、时间、时间戳和固定宽度 Binary。
- Avro OCF：读取 JSON schema、文件元信息和数据块，显示前 100 行；支持 null 与 deflate codec，以及 primitive、record、union、enum、fixed、array 和 map。
- Arrow 的嵌套、字典编码或 IPC body compression 会安全回退为 schema 表格，不尝试不完整解码。
- 所有解析都在 Quick Look 扩展内只读完成，不启动外部进程、不联网，也不依赖用户安装 Python 或数据工具链。
- 文件读取上限 64 MiB、数据预览上限 100 行、可见列上限 100；FlatBuffer、Thrift 和 Avro 的偏移、长度、节点数与嵌套深度均受检查。

## 自动验证

- PyArrow 21.0.0 生成的 Parquet、Arrow IPC、Feather v2 标准文件。
- fastavro 1.12.1 生成的 null 与 deflate Avro OCF 文件。
- 中文、NULL、整数、浮点、布尔、schema、行组和创建器元信息。
- 120 行 Arrow/Avro 截断为 100 行，并准确记录 20 行未显示。
- 嵌套 Arrow List 安全回退到 schema 表格。
- 损坏 Parquet/Arrow/Avro 和 Feather v1 返回明确错误。
- 全部核心测试 44 项通过。
- arm64/x86_64 Release 构建和严格签名校验通过。

## Finder 验收

- 系统自动调用已验证：Parquet、Arrow IPC、Feather v2、Avro deflate 均由 SpaceLens 成功渲染且未截断。
- 用户已确认：Parquet schema/元信息、Arrow IPC 表格、Feather v2 表格、Avro deflate 表格均正常显示。
- Finder 文件种类分别显示为 Apache Parquet、Apache Arrow IPC、Apache Feather 和 Apache Avro。

## 已知限制

- Parquet 当前显示 schema 与文件级元信息，不解码数据页；不同压缩算法不影响元信息预览。
- Arrow IPC stream（无 `ARROW1` 文件头）、Feather v1、字典编码、嵌套列和 IPC body compression 不显示数据行。嵌套/字典/压缩 IPC 文件仍显示 schema；Feather v1 给出转换提示。
- Avro 当前支持 null 和 deflate codec；snappy、bzip2、xz、zstandard 等 codec 返回明确提示。
- 单文件超过 64 MiB 时拒绝读取，避免 Quick Look 扩展占用过多内存。
