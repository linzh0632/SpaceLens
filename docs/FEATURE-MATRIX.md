# 支持格式与限制

SpaceLens 以只读方式生成 Quick Look 预览。下表描述当前版本实际支持的范围。

| 类别 | 格式或内容 | 预览方式与限制 |
|---|---|---|
| 文件夹 | 普通文件夹 | 可展开树；名称、类型、大小、修改时间；最多 10,000 项、10 层 |
| ZIP | `.zip` | 可展开树；包内常见图片、文本、代码、文档和结构化数据可在右侧窗格预览 |
| 其他归档 | `.tar`、`.gz`、`.tgz`、`.bz2`、`.tbz2`、`.xz`、`.txz` | 只读条目与元数据；独立压缩流显示为单个条目 |
| 文本与代码 | 常见源代码、配置、日志、diff、SQL、GraphQL、Makefile 等 | UTF-8、UTF-16；最多读取 5 MiB、显示 1,000 行；常见语言语法着色 |
| Markdown 与技术文档 | `.md`、`.mdx`、`.qmd`、`.rmd`、`.rst`、`.rest`、`.adoc`、`.asciidoc`、`.tex` | 本地排版；不执行脚本、宏或文档代码，不加载远程资源 |
| Notebook | `.ipynb` | 显示 Markdown、代码和文件内已有的文本输出；不运行单元格 |
| 表格与结构化文本 | `.tsv`、`.json`、`.jsonl`、`.ndjson` | 表格或可展开结构树；最多 1,000 行，JSON 最多 10,000 个节点、50 层 |
| Office 表格 | `.xlsx`、`.xlsm` | 只读显示第一个工作表为表格；公式不求值（显示文件里已缓存的值），不读取宏；最多 400 行、60 列，单元格文字照原样显示 |
| Property List | XML、Binary、OpenStep plist | 可展开键、类型和值；损坏文件显示错误提示 |
| SQLite | `.db`、`.sqlite`、`.sqlite3` | 只读显示用户表、列定义及每表最多 100 行样本 |
| 图表 | Mermaid、MMD、PlantUML、PUML、Draw.io | 本地 SVG；支持常见流程图、关系图和时序图语法，不调用外部渲染器 |
| 列式数据 | Parquet、Arrow IPC、Feather v2、Avro OCF | schema、元数据和前 100 行；复杂或压缩 Arrow 列可能只显示 schema |
| 系统原生格式 | 图片、PDF、音频、视频等 | 继续使用 macOS 原生 Quick Look |

## 容器内预览限制

文件夹中的条目可以复用 SpaceLens 支持的预览器。ZIP 条目在内存中读取，不会先解压到磁盘；其中需要独立文件路径的 SQLite、Parquet、Arrow、Feather、Avro、PDF 和嵌套归档暂不支持右侧窗格预览，并会显示明确提示。

`.xlsx` 与 `.xlsm` 需要同时读取包内多个成员，目前只在**文件夹**的右侧窗格支持；压缩包内的这类文件仍会提示暂不支持。

## macOS 的处理器优先级

macOS 可能优先使用系统或其他应用提供的 Quick Look 扩展。SpaceLens 不会关闭其他扩展，也不会把自己注册成文件的默认打开应用。在 macOS 27 上，CSV 与普通 TXT 通常由系统预览处理。
