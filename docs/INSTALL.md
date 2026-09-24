# SpaceLens 本机安装与验收

当前为 0.5.1（构建 14），M1 至 M6 已完成并通过自动检查与 Finder 实机验收。支持专用 `.spacelens` 文件、递归文件夹树、常用归档，以及文本、扩展代码与配置格式、Markdown、CSV/TSV、JSON/JSON Lines、plist、SQLite、扩展文档、Jupyter Notebook、Mermaid、PlantUML、Draw.io、Parquet、Arrow、Feather 和 Avro；文件夹与归档列表显示修改时间。

## 构建与安装

需要完整 Xcode，首次启动已完成。在项目根目录执行：

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/install.sh
```

默认安装到 `/Applications/SpaceLens.app`。如系统要求目录写入许可，允许本次安装即可。脚本使用本地 ad hoc 签名，不需要付费证书。**这个安装方式仅在本机验证过，不是经过 Apple 公证的分发包。**

构建和测试产物默认放在系统临时目录，以避免同步文件夹附加的 Finder 元数据破坏签名。可设置 `SPACELENS_DERIVED_DATA` 和 `SPACELENS_TEST_BUILD` 指向其他非同步本地目录；安装时要使用与构建时相同的 `SPACELENS_DERIVED_DATA`。

也可以用 Xcode 打开 `SpaceLens.xcodeproj`，选 SpaceLens scheme，签名保持 Sign to Run Locally。首次构建时让 Derived Data 保持默认本机位置。

## 使用

1. 打开 SpaceLens，点击“创建验收文件…”保存 Hello.spacelens。
2. 在 Finder 选中文件按空格，应出现“SpaceLens · 验收文件”。
3. 选择普通文件夹按空格，应出现“SpaceLens · 文件夹”，列表显示名称、类型、大小和修改时间，最多读取 10,000 项和 10 层。**右窗格默认收起**；点击列表中的文件后自动展开并就地预览其内容（图片、文本、代码、Markdown、表格、结构树、图表），点击文件夹行或取消选中时重新收起；分隔条可拖拽调整宽度。
4. 选择 ZIP 按空格，应显示归档条目、大小、压缩方法和修改时间；点击条目同样会在右侧窗格预览内容。归档条目的内容在**内存中**解析，SpaceLens 不会解压到磁盘；归档内的 SQLite、列式数据（Parquet/Arrow/Feather/Avro）与嵌套压缩包不支持在窗格中预览，会给出明确提示。容器内的 PDF 也不在窗格中预览。
5. 选择 Markdown 或代码文件，应显示 SpaceLens 排版或语法着色；选择 TSV 应显示 SpaceLens 表格；选择 JSON/JSON Lines 应显示可展开结构树。
6. 选择 CSV 和普通 TXT，应继续显示 macOS 原生预览。在 macOS 27 上，这两类文件由系统内置 Office/Text 生成器优先处理，SpaceLens 不强行移除或禁用系统生成器。
7. 选择 TAR、TGZ、TBZ2、TXZ，应显示 SpaceLens 的可展开归档树和修改时间列；选择独立 GZ/BZ2/XZ，应显示一个压缩数据条目。
8. 选择 XML 或二进制 plist，应显示可展开的键、类型和值；选择 `.db`、`.sqlite` 或 `.sqlite3`，应显示用户表、列定义和每表最多 100 行只读样本。
9. 选择 MDX、QMD、RMD、RST、AsciiDoc 或 TeX，应显示标题、正文和代码块；选择 IPYNB，应显示 Markdown、代码与文件内已有的文本输出。SpaceLens 不运行 Notebook 单元格。
10. 选择 `.mermaid`/`.mmd`、`.puml`/`.plantuml` 或 `.drawio`，应显示 SpaceLens 的本地图表画布。支持 Mermaid 流程图与时序图、PlantUML 基础关系与时序图，以及压缩或未压缩 Draw.io XML。
11. 选择 `.parquet`，应显示字段 schema、行数、行组和文件元信息；选择 `.arrow`/`.feather` 或 `.avro`，应显示字段和前 100 行数据。复杂或压缩 Arrow 列显示 schema。
12. 选择 `.zig`、`.f90`、`.proto`、`.tfvars`、`.sv` 或 Makefile，应显示 SpaceLens 代码预览和对应语言名称。README、LICENSE、CMakeLists.txt 可能继续由系统原生文本预览处理。
13. 若没有出现，打开系统设置，查找“登录项与扩展”中的 Quick Look，启用 SpaceLens。不同系统版本的入口可能不同。

本机已有 Looq。若同类文件被它接管，需要在系统设置中选择预览扩展。SpaceLens 不会自动关闭其他应用的扩展，也不会注册图片、PDF、音视频等通用类型。 SpaceLens 主应用不声明任何可打开文档类型，只提供 Quick Look 预览；双击文件仍交给系统或用户选择的编辑器。

## 更新

先退出 SpaceLens、关闭它的预览窗口，然后：

```sh
./scripts/build.sh
./scripts/install.sh --replace
```

安装脚本检查原应用身份，并将旧版保留在输出所示的临时备份目录。若更新失败，可将其中 `SpaceLens.previous` 恢复为 `/Applications/SpaceLens.app`。旧备份会随系统临时目录清理消失；它不替代 Git 版本控制。

## 卸载与撤销

退出 SpaceLens、关闭预览窗口，然后运行 `./scripts/uninstall.sh --remove`。脚本核对应用身份、注销 Quick Look 扩展并将应用移入废纸篓。不要删除或禁用 Looq 等其他应用。已保存的验收文件可自行保留或删除，源码仓库不受影响。

如果系统仍显示旧注册项，可运行：

```sh
pluginkit -r /Applications/SpaceLens.app/Contents/PlugIns/SpaceLensPreview.appex
```

此命令应在移动应用前执行。Finder 的短时缓存不代表应用仍然安装；关闭后重新打开预览再检查，必要时重新登录。

## 验收清单

- [x] 本机 `.spacelens` 预览显示 SpaceLens 标识（用户确认）
- [x] 本机文件夹预览显示 SpaceLens 标识（用户确认）
- [x] 应用退出后覆盖安装、再次启动、已启用的扩展注册保留
- [x] 更新后 Finder 再次预览（用户确认正常）
- [x] 原生 PNG/PDF/WAV/MOV 预览（用户确认全部正常）
- [x] XML/Binary plist 与 DB/SQLite/SQLite3 预览（用户确认全部正常）
- [x] MDX/QMD/RMD/RST/REST/ADOC/ASCIIDOC/TeX/IPYNB 预览（用户确认全部正常）
- [x] Mermaid/MMD、PlantUML/PUML 与压缩/未压缩 Draw.io 预览（用户确认全部正常）
- [x] Parquet、Arrow、Feather、Avro 预览（用户确认全部正常）
- [x] 92 个文件及文件夹样例的默认打开应用审计（SpaceLens 未接管任何双击打开操作）
- [x] Zig、Fortran、Protocol Buffers、Terraform、SystemVerilog 与 Makefile 预览（用户确认全部正常）
- [x] 文件夹、ZIP 与归档列表的“修改时间”列，日期跟随系统首选界面语言（用户确认）
- [x] 整机重启后 Quick Look 预览正常（用户实机确认）
- [x] 文件夹条目在右侧窗格就地预览（图片、纯文本、代码、Markdown；用户确认）
- [x] ZIP 条目在右侧窗格就地预览（图片、Markdown；用户确认）
- [ ] 窗格内 JSON/CSV/图表与加密归档条目的视觉确认（核心路径已有自动测试）
- [ ] 其他 macOS 版本及 Intel 实机（尚未验证）

原生图片/PDF/音频/视频样例可用 `xcrun swift scripts/create-native-fixtures.swift build/NativeFixtures` 生成。视频生成器使用兼容旧 SDK 的 API，在 macOS 27 上会给出弃用警告，不影响产品代码。生成文件不进入仓库。
