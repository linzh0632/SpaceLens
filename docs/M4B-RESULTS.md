# M4B plist 与 SQLite

状态：核心实现、自动测试、Release 构建、本机安装、扩展调用和 Finder 视觉验收全部完成。

## 实现范围

- XML、Binary 和 OpenStep plist：可展开显示字典、数组、字符串、数字、布尔值、日期和 Data。
- plist 最多读取 20 MiB、展示 10,000 个节点和 50 层；长字符串截断为 500 个字符。
- SQLite：支持 `.db`、`.sqlite`、`.sqlite3`，显示最多 50 个用户表、每表最多 100 列和 100 行样本。
- 显示列声明类型、主键、非空与默认值，并区分整数、浮点数、文本、BLOB 和 NULL。
- 数据库以 SQLite 只读模式打开，不创建 journal/WAL，不执行写入；虚拟表只展示结构，避免加载扩展模块。
- 所有处理均在本机完成，不执行文件内代码，不上传内容。

## 自动验证

- XML 与 Binary plist 的嵌套结构、类型、排序和格式说明。
- 损坏 plist 返回明确错误。
- SQLite 表结构、105 行截断到 100 行、带引号标识符、BLOB、空数据库和损坏数据库。
- 验证数据库预览不产生 journal 或 WAL 文件。
- 全部核心测试 33 项通过。
- arm64/x86_64 Release 构建和严格签名校验通过。
- 0.4.1 build 7 已覆盖安装并刷新 Quick Look 缓存。
- 系统识别 plist 为 `com.apple.property-list`；新建 SQLite 文件由 SpaceLens 自有 UTI 接管，同时兼容已有 `.db` 文件的 `org.sqlite.database`。
- XML plist、Binary plist、`.db`、`.sqlite` 和 `.sqlite3` 均已单独调用 `qlmanage`，SpaceLens 日志记录五次成功渲染且均未截断。

## Finder 验收

- 2026-09-24 用户逐项预览 XML plist、Binary plist、`.db`、`.sqlite` 和 `.sqlite3`，确认均成功显示。

## 已知限制

- SQLite 仅显示用户表，不显示视图、触发器、索引或系统表。
- 虚拟表不读取样本数据；加密数据库及非 SQLite 的通用 `.db` 文件会显示无法读取。
- plist 不反序列化归档对象，只展示 Foundation 属性列表能够安全解析的值。
- 大型数据库的“行数”是当前读取到的样本数，不执行全表 `COUNT(*)`。
