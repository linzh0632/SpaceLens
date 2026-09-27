# M4C 扩展文档与 Jupyter Notebook

状态：核心实现、自动测试、Release 构建、本机安装、扩展调用和 Finder 视觉验收全部完成。

## 实现范围

- MDX、Quarto Markdown（QMD）和 R Markdown（RMD）复用安全的本地 Markdown 排版。
- reStructuredText（RST/REST）识别下划线标题与 `code-block`，转换为只读预览结构。
- AsciiDoc（ADOC/ASCIIDOC）识别标题、源码块和普通正文。
- TeX 识别 chapter/section/subsection、item 与 verbatim/listing 代码块；公式和未识别命令保持源码可见。
- Jupyter Notebook（IPYNB）显示 Markdown、代码、raw 单元格，以及文件中已经保存的纯文本输出和错误信息。
- Notebook 最多显示 200 个单元格、每个代码单元格最多 20 个输出、单项输出最多 10,000 字符；输入仍受 5 MiB 文本上限约束。
- 不执行 MDX 组件、文档代码块、TeX 命令或 Notebook 单元格，不读取远程资源。

## 自动验证

- MDX、QMD、RMD 的分类、格式名称和正文保持。
- RST、AsciiDoc、TeX 的标题和代码块转换。
- IPYNB 的 Markdown、Python 代码、stream 输出、`text/plain` 输出和 raw 单元格。
- Notebook 缺失必要字段时返回明确错误；超过 200 个单元格时截断。
- 全部核心测试 37 项通过。
- arm64/x86_64 Release 构建和严格签名校验通过。
- 0.4.2 build 8 已覆盖安装并刷新 Quick Look 缓存。
- 系统既有的 ADOC `com.unknown.adoc` 与 TeX `org.tug.tex` 标识已登记，其余扩展名由 SpaceLens 自有 UTI 接管。
- 九种扩展名均已逐项调用 `qlmanage`，SpaceLens 日志记录九次成功渲染且均未截断。

## Finder 验收

- 2026-09-24 用户逐项预览 MDX、QMD、RMD、RST、REST、ADOC、ASCIIDOC、TeX 和 IPYNB，确认功能正常。

## 已知限制

- 这是安全的轻量结构预览，不是 Pandoc、Quarto、LaTeX、Jupyter 或 Asciidoctor 的完整渲染器。
- MDX 的 React 组件、Quarto/R Markdown 的计算块只显示源码。
- IPYNB 的图片、HTML、JavaScript 和交互式输出不渲染；仅显示纯文本表示。
- TeX 不排版公式、不解析宏、不访问包含文件。
