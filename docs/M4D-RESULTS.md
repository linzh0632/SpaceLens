# M4D 本地图表预览

状态：核心实现、自动测试、通用 Release 构建、本机安装、扩展调用和 Finder 视觉验收全部完成。

## 实现范围

- Mermaid/MMD：渲染 `flowchart`、`graph` 与 `sequenceDiagram` 的常用节点、关系、标签和参与者。
- PlantUML/PUML：渲染常用节点关系与时序消息；识别 `@startuml`/`@enduml`、participant 和 actor。
- Draw.io：读取常见的压缩或未压缩 XML，显示顶点、连线、标签、位置与基本矩形/椭圆外形。
- 所有格式均在 Quick Look 扩展内转成只读 SVG，不启动外部命令，不加载脚本，不请求网络资源。
- 输入上限 5 MiB；单图最多处理 500 行或元素，时序图最多显示 20 个参与者，超限时标记为截断。
- 文件内容和 Draw.io 标签在写入 SVG 前转义，避免标签注入可执行标记。

## 自动验证

- Mermaid 流程图、分支节点、边标签与时序图。
- PlantUML 时序请求和响应。
- 压缩及未压缩 Draw.io XML 的节点、连线、标签和几何信息。
- SVG 标签转义、损坏压缩数据与不支持语法的明确错误。
- 全部核心测试 41 项通过。
- arm64/x86_64 Release 构建和严格签名校验通过。
- 0.4.3 build 9 已覆盖安装并刷新 Quick Look 缓存。
- 七个样例扩展名均解析为 SpaceLens 自有 UTI；逐项调用 `qlmanage` 后，SpaceLens 日志记录七次成功渲染且均未截断。

## Finder 验收

- 2026-09-24 用户逐项预览 Mermaid/MMD、PlantUML/PUML，以及压缩和未压缩 Draw.io，确认显示正常。

## 已知限制

- 这是轻量、安全的结构预览，不是 Mermaid、PlantUML 或 Draw.io 的完整排版引擎。
- 不支持 Mermaid 饼图、甘特图、状态图等高级语法，也不解释 class/style/theme 指令。
- 不支持 PlantUML include、宏、皮肤、远程资源及复杂容器。
- Draw.io 只显示基础顶点、连线、标签和矩形/椭圆，忽略图片、HTML 富文本、泳道、复杂路径和样式细节。
- SpaceLens 不执行图表中的链接、脚本或外部引用。
