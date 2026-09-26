# 文件关联说明

SpaceLens 是 Quick Look 预览扩展，不是通用文件编辑器或打开程序。

- 主应用不声明 `CFBundleDocumentTypes`，不会出现在普通文档的“打开方式”列表中。
- Markdown、代码、配置、结构化数据、归档、SQLite、图表和列式数据只注册为可预览类型。
- 双击文件时，macOS 仍会使用原有默认应用。
- 图片、PDF、音频和视频等通用类型继续由系统原生 Quick Look 处理。
- `.spacelens` 仅用于检查扩展是否安装成功；它也不会让 SpaceLens 接管其他文件。

项目的自动检查会阻止主应用重新声明文档打开角色，并检查导入格式的显示名称不含 SpaceLens 品牌。
