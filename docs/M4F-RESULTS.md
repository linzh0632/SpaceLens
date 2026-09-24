# M4F 代码与配置预览结果

## 范围

M4F 对照 Super Quick Look 官网公开展示的代码与配置样例，扩展 SpaceLens 的本地文本识别、语言名称和 Quick Look 路由。核心加载器覆盖 72 个公开样例名称，包括 Assembly、AWK、Bazel、CMake、CoffeeScript、Crystal、D、Fortran、GDScript、Gradle、Groovy、HCL、Haskell、Julia、OCaml、Nim、Nushell、Protocol Buffers、Raku、Racket、Scheme、Solidity、SystemVerilog、Tcl、Terraform、Verilog、XML Schema、XSLT 和 Zig。

新增 49 个安全扩展名注册，并补充系统已有的 Make、Assembly、Fortran、Groovy、Haskell、OCaml 和 Protocol Buffers UTI。所有声明都属于 Quick Look 预览扩展；主应用继续不声明 `CFBundleDocumentTypes`，因此不会成为这些文件的双击默认打开应用。

## 验证

- [x] 72 个官网代码与配置样例均由核心加载器识别为代码预览
- [x] 自动化测试：46 项，0 失败
- [x] 两个 Info.plist 语法检查通过
- [x] 主应用未声明任何文档打开类型
- [x] 58 个阶段样例的默认打开应用审计：SpaceLens 接管数量为 0
- [x] Release 构建与覆盖安装（0.4.6，build 12）
- [x] Finder/Quick Look 自动路由检查（6 个代表样例全部渲染成功）
- [x] Finder 视觉验收（Zig、Fortran、Protocol Buffers、Terraform、SystemVerilog 与 Makefile 均由用户确认正常）

## 安全边界与已知限制

- SpaceLens 不注册宽泛的 `public.data`。Dockerfile、无扩展名 `build` 和 `workspace` 在当前系统会落到该类型；核心可以渲染它们，但 Finder 是否交给 SpaceLens 取决于系统和其他扩展，避免为三个文件名接管所有未知数据文件。
- README、LICENSE 和 CMakeLists.txt 在当前系统属于 `public.plain-text`，可能继续使用系统原生文本预览。
- `.ts` 在当前系统可表示 MPEG-2 传输流，`.r` 可表示 Rez 源码；SpaceLens 不以扩展名强制覆盖这些冲突类型。
- `.xsd`、`.xsl`、`.xslt` 在装有 Looq 的当前机器上可能解析为 `com.looq.xml`。SpaceLens 支持该已注册类型，但最终使用哪个 Quick Look 扩展仍由 macOS 决定。
- 文本读取仍限制为 5 MiB、最多 1,000 行和每行 20,000 个字符；内容完全在本地处理。

## 验收样例

本阶段样例曾位于 `build/fixtures/m4f`，仅用于开发验收且未提交到 Git。用户确认视觉验收正常后，样例目录已按约定删除。
