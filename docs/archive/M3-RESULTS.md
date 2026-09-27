# M3 常用文本格式

状态：核心实现、自动测试、Release 构建、本机安装与逐类视觉验收完成；CSV 与普通 TXT 保留 macOS 原生预览，原因见限制。

## 实现范围

- 文本与代码：UTF-8、带 BOM 的 UTF-16 LE/BE，最多读取 5 MiB；代码和常见配置采用完全本地的通用语法着色。
- Markdown：基础标题、段落、列表、引用和围栏代码块排版；不创建 WebView，不执行 HTML、脚本、宏或文档代码，不请求网络资源。
- CSV/TSV：支持引号单元格、转义引号、逗号和换行，动态列和横向滚动；最多显示 1,000 行、100 列。
- JSON：对象和数组以可展开树显示，键按稳定顺序排列；JSON Lines/NDJSON 按行建立根节点。
- JSON 最多构建 10,000 个节点、50 层；达到上限立即停止继续构树。
- 输入取消、错误编码、未闭合 CSV 引号和损坏 JSON 均返回明确提示。

## 验收状态

| 项目 | 状态 |
|---|---|
| 核心自动测试 | 25 项通过，0 失败 |
| Release 构建与严格签名 | arm64/x86_64 通用构建通过；宿主与扩展签名校验通过 |
| 本机安装与扩展注册 | 0.3.0 build 4 已安装并启用；Quick Look 缓存已刷新 |
| macOS 类型识别 | 已按系统实际 UTI 逐项登记，不再依赖父类型匹配 |
| Quick Look 扩展调用 | Markdown、Swift、TSV、JSON、JSONL 已记录 SpaceLens 成功渲染 |
| 原生预览共存 | CSV 由系统 Office 生成器显示；普通 TXT/UTF-16 TXT 由系统 Text 生成器显示 |
| 用户视觉验收 | 2026-09-23 确认：除 CSV 与普通 TXT 外，其余本轮样例均通过 SpaceLens 打开 |

## 已知限制

- Markdown 是安全的基础排版，不含 CommonMark 全语法、表格、脚注、数学公式或图表渲染。
- 通用代码着色不等同于完整语言语法解析；嵌套字符串和少数语言构造可能着色不精确。
- Quick Look 扩展的 `QLSupportedContentTypes` 必须登记精确 UTI，登记 `public.source-code` 等父类型不会自动覆盖 Swift、Markdown 等子类型。build 4 已改为精确登记。
- macOS 27 会对其原生支持的 CSV 和普通 TXT 优先使用 `/System/Library/QuickLook/Office.qlgenerator` 与 `Text.qlgenerator`。SpaceLens 的解析器和界面已经实现并通过测试，但在当前系统的 Finder/`qlmanage` 中不会得到调用；保留系统结果可避免破坏原生 Quick Look。
- `.ts` 在当前系统被识别为 MPEG-2 transport stream，`.r` 被识别为 Rez source，`.markdown` 被识别为通用 data container；SpaceLens 不会声明这些不准确的系统 UTI，以免抢占真实视频、Rez 源码或任意数据文件。对应的 `.tsx`、`.md` 以及无冲突的代码扩展名可正常接管。
- 无扩展名的 Dockerfile、Makefile、LICENSE 等文件受系统 UTI 分配影响，不能通过注册 `public.data` 强行接管，否则会破坏原生格式共存。
- CSV 自动使用第一行作为列名，暂不提供分隔符和表头手动设置。
