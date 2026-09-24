# 文件类型与默认打开应用审计

状态：已完成。SpaceLens 主应用仅承载设置和 Quick Look 扩展，不注册为任何文档的打开程序。

## 修复内容

- 删除主应用的 `CFBundleDocumentTypes`，因此 SpaceLens 不再进入文件的“打开方式”候选，也不会成为双击默认应用。
- 仅将 `.spacelens` 声明为 SpaceLens 自有验收格式。
- Markdown、代码、配置、结构化文本、归档、SQLite、扩展文档、Notebook、图表和数据格式均声明为导入类型，并使用中性格式名称。
- Quick Look 扩展继续注册全部受支持 UTI，按空格预览能力不受影响。
- 新增回归测试，阻止主应用重新声明文档打开类型，并检查非自有格式名称不含 SpaceLens。

## 本机验证

- 45 项核心测试通过。
- arm64/x86_64 Release 构建与严格签名校验通过。
- 在项目 `build/fixtures/file-associations` 临时生成并审计 92 个文件及文件夹样例；没有任何项目以 SpaceLens 为默认打开应用。
- 除 `.spacelens` 验收文件外，所有样例的 Finder 类型名称均不包含 SpaceLens。
- 安装 0.4.5 后，Markdown 与自定义配置类型仍由 SpaceLens Quick Look 扩展成功渲染。
- 临时样例已在验证结束后删除。

`.spacelens` 是项目专用验收文件，因此保留“SpaceLens Acceptance Sample”种类名称；它也不会默认双击打开 SpaceLens。
