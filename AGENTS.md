# SpaceLens

- 用户要求：使用 Git；大功能完成并通过相关验证后推送到指定 GitHub 仓库。
- 私有仓库目标：linzh0632/SpaceLens；未经用户要求不改为公开。
- 当前已实现 M1 接入原型，验收状态见 docs/M1-RESULTS.md。参照 SpaceLens-PREPARATION.md，不把计划写成已实现功能。
- Swift 原生应用与 Quick Look 扩展为候选方案，优先验证 Finder 文件夹接入和原生格式共存。
- 文件解析和预览在本地完成；不执行预览内容中的代码，不上传用户文件。
- 每个里程碑更新 README、验证记录和限制。提交前检查暂存差异，不提交凭证或个人样本。
- 阶段性临时验收文件统一生成在项目内 `build/fixtures/<里程碑>`；验收完成后立即删除，不在桌面遗留测试文件。
