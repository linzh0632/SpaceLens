# M7 容器内条目预览（设计）

状态：**设计稿，未实现**。两个阻塞项已验证通过（见下），但功能本身尚未编码；实现完成前不更新 README 的功能清单。

目标：在文件夹、ZIP 与其他归档的树形列表中点击某个文件条目时，在窗口**右侧**的预览窗格中显示该条目的内容（图片、文档、代码、文本等），无需离开当前预览窗口。

## 非目标

- 不在右窗格内继续深入嵌套容器（归档里的归档、ZIP 里的 ZIP）。
- 不写入磁盘、不生成临时文件、不调用外部进程、不请求网络。
- 不调用系统 Quick Look，也不调用外部应用打开条目。
- 不改变双击打开行为：主应用继续不声明任何文档角色。
- 不改动系统原生图片、PDF、音视频的预览路径（扩展不声明这些 UTI）。

## 可行性核实（代码依据）

| 事项 | 结论 | 依据 |
|---|---|---|
| 文件夹子项**元数据** | 已证明可读 | `DirectoryPreview.load` 递归 10 层读取子项 `fileSize`/`contentModificationDate`，M2 验收通过 |
| 文件夹子项**内容** | **已实测通过** | 真实 Quick Look 扩展内的探针实验，含嵌套子目录；见下节 |
| 归档条目**内容** | **已实测通过** | 独立探针按条目抽取并做 SHA-256 比对；见下节。`archive_read_data_skip`（`ArchivePreview.swift:114`）处换成有上限的 `archive_read_data` 循环 |
| **ZIP** 条目内容 | 不能复用现有实现，改走 libarchive | `ZipPreview` 是手写中央目录解析，只读元数据：未解析 local header 偏移，也无 zlib 依赖，**无法取数据** |
| 图片解码 | 当前完全没有 | `CommonTextPreview` 对 `.png` 等直接抛 `unsupported`；需引入 ImageIO 缩略图解码 |

保留 `ZipPreview` 的手写解析用于**列表**（它的 ZIP64 检测、加密标记、异常压缩比告警是 libarchive 列表不具备的信息），内容层统一走 libarchive。

## 阻塞项验证结果（已完成，全部通过）

按 M1 的接入验证纪律，先实验再扩充。两项实验均已执行。

### 1. 沙盒子项内容读取 — 通过

方法：在扩展中加入临时探针（只记录层数、扩展名、结果，不记录文件路径），装机后用 Finder 实际按空格预览一个含嵌套子目录的测试文件夹，再读取扩展写入的系统日志。探针已删除，机器上已装回与源码一致的干净版本。

```
m7probe summary inspected=5 opened=5 depth1=4 deeper=1 failed=0
  depth=1 ext=md     bytes=29  result=ok
  depth=1 ext=swift  bytes=20  result=ok
  depth=1 ext=bin    bytes=64  result=ok
  depth=2 ext=txt    bytes=13  result=ok   ← 嵌套子目录内容读取同样成功
  depth=1 ext=txt    bytes=16  result=ok
```

结论：`com.apple.security.files.user-selected.read-only` 对文件夹的授权**覆盖子项内容，且覆盖嵌套子目录**。文件夹来源可用，右窗格不需要额外沙盒权限或用户授权流程。

### 2. libarchive 抽取归档条目数据 — 通过

方法：一次性独立探针（`@_silgen_name` 方式链接 `-larchive`，与 `ArchivePreview.swift` 相同做法），对各类归档按路径定位条目并读入内存，与原文件做 SHA-256 比对。

| 场景 | 结果 |
|---|---|
| deflate ZIP 条目 | 抽取成功，SHA-256 与原文件一致 |
| store（未压缩）ZIP 条目 | 成功，一致 |
| TAR.GZ 条目（两个条目） | 成功，一致 |
| 加密 ZIP 条目 | 被拒绝：`Passphrase required for this entry`；`archive_entry_is_encrypted` 正确返回 true |
| 上限截断（1 KiB 上限读 256 KiB 条目） | 到上限即停，标记 `hitLimit`，内存不失控 |
| 性能 | 201 条目 ZIP 抽取最后一条，扫描 184 条耗时 2 ms |

结论：ZIP 与 TAR 系列都能在内存中按条目抽取，加密条目可被明确拦截；限额策略有效。因此 **ZIP 内容层走 libarchive 可行**，不必给现有手写解析器补 local header 解析与 zlib 依赖。

## 架构

### Core 新增

```
public enum EmbeddedPreviewLoader {
    public enum Source: Sendable {
        case directoryChild(root: URL, relativePath: String)  // 真实文件夹内的子项
        case archiveEntry(archive: URL, path: String)         // 归档内条目
    }
    public static func load(_ source: Source) throws -> PreviewSnapshot
}
```

两类来源的支持范围**不同**，因为既有解析器大多以文件 URL 为输入：

- **文件夹来源 — 全部类型**：拼出子项 URL 后直接调用 `PreviewLoader.load`，因此嵌套 ZIP、SQLite、JSON、CSV、代码、列式数据等全部自动可用，且不需要改动任何既有解析器。这是"完全复用"的主要收益。
- **归档来源 — 文本类 + 图片**：条目不落盘，因此只能用**能从内存解析**的类型：
  - 图片：新增 ImageIO 分支。
  - 文本/代码/Markdown/表格/JSON/plist：既有实现里 `loadStructured`、`loadTable` 已经接收 `source: String`，只需把入口从 URL 改为可从 `Data` 进入。
  - **不支持**：SQLite、Parquet、Arrow、Feather、Avro、以及归档内的嵌套容器——这些解析器需要文件路径，落盘与"不写磁盘"约定冲突，v1 明确提示而不支持（见"安全与边界"）。

### PreviewSnapshot 扩展

- 新增 `ContentKind.image`。
- 新增 `imagePNGData: Data?`：缩略图重编码为 PNG 后携带。这样天然满足 `Sendable`，避免 `CGImage` 跨并发边界（工程为 `SWIFT_STRICT_CONCURRENCY = complete`）。

### 抽取限额

| 限制 | 值 | 理由 |
|---|---|---|
| 单条目解压上限 | 16 MiB | 图片可能较大；超出则只显示元信息并明确提示 |
| 文本读取上限 | 5 MiB（沿用） | 复用现有 `CommonTextPreview` 预算 |
| 图片像素上限 | 解码 4096 px，展示缩略图 ≤ 2048 px | 防图片解压炸弹 |
| 归档扫描超时 | 3 秒 | tar 系列为顺序扫描，超时后提示而不是无限等待 |
| 右窗格缓存 | 8 项 / 32 MiB（LRU） | 上下键连续切换时的响应 |

防解压炸弹：边读边计数，达到上限立即停止并提示"条目过大，仅显示元信息"；不做递归解压。

## 交互与界面

- 容器类内容（`.directory`/`.zip`/`.archive`）的主视图由当前单一滚动视图改为 **`NSSplitView`**：左侧树（最小 320 pt），右侧预览窗格（最小 300 pt），分隔条可拖拽。
- 右窗格初始态："选择左侧文件以预览"。
- 选中变化 → 取消上一个加载任务（沿用现有 `generation` UUID 竞态防护模式）→ `Task.detached` 后台加载 → 渲染。
- 快捷切换：方向键连续移动选择时，前一个任务被取消，只有最后一次选择渲染。
- 右窗格只显示自身错误，**不替换左侧树**；归档条目额外标注"内容在内存中解析，未写入磁盘"。
- 点击文件夹条目仍是展开/折叠，不触发加载；只有叶子文件加载内容。
- 非容器类内容（`.structured`/`.table`/`.text`/`.diagram` 等）主视图保持现状，不显示分隔。

## 复用的现有实现

- 文本/代码/Markdown 渲染：`highlightCode`、`renderMarkdown`（`PreviewViewController.swift:578`、`:599`）。两者是文件私有自由函数，提取右窗格时可直接复用。
- 加载与竞态：`PreviewLoader.load`、`generation` 模式、`renderError`。
- 上限与限制提示：`PreviewFailure` 文案体系与摘要后缀风格。

## 需要的小重构

1. `PreviewNode` 增加 `fullPath: String`（在 `makeTree` 中逐层累积）。当前只存 `name`（`:390`），无法定位条目来源。
2. 新增 `outlineViewSelectionDidChange`：工程当前没有任何选择回调。
3. 右窗格渲染器独立为 `DetailPreviewPane`，避免与主视图状态耦合；主视图改为持有它。
4. **新增 Core 文件必须手改 `SpaceLens.xcodeproj/project.pbxproj`**：工程只有 47 行且使用逐文件显式引用（无 Xcode 16+ 的文件系统同步组），每个源文件都要有 `PBXFileReference` + `PBXBuildFile`，并加入扩展 target 的 Sources build phase。SwiftPM 侧（`Package.swift` 的 `Sources/Core`）会自动包含新文件，两边都要验证。

## 安全与边界

- 沿用：不执行预览内容中的代码、不渲染 HTML 外部资源、不请求网络、不跟随符号链接、拒绝 FIFO 等非普通文件。
- 归档条目路径只用于**在归档内定位**，不参与任何磁盘路径拼接，因此不存在解压路径越界问题。
- 加密条目、ZIP64 条目、损坏归档：明确提示"无法预览内容"，不静默回退成空白。
- 归档内需要文件路径的类型（SQLite、列式数据）与嵌套容器：明确提示不支持，避免为了预览而落盘。
- 图片仅解码为位图；SVG 等非位图格式仍不支持。

## 分期

- **M7a**：选中回调与 `NSSplitView` 右窗格 + `EmbeddedPreviewLoader` 的文件夹来源（完全复用 `PreviewLoader`）+ 归档来源的图片与文本/代码/文档。
- **M7b**：归档来源补齐表格与结构化类型（CSV/JSON/plist 从 `Data` 进入）+ LRU 缓存与性能调优。

每个分期更新 README、`docs/M7-RESULTS.md` 与 `docs/FEATURE-MATRIX.md`，并如实区分已测与未测。

## 验收标准

- [x] 沙盒子项内容读取实验结论已记录（通过，见上）
- [ ] 文件夹内 PNG/JPG/Markdown/Swift 条目点击后右窗格正确显示
- [ ] ZIP 与 TAR.GZ 内同类条目点击后右窗格正确显示
- [ ] 加密 ZIP 条目给出明确提示且不崩溃
- [ ] 归档内 SQLite/列式数据给出"不支持"的明确提示，且确认未写盘
- [ ] 10,000 项目录：点击响应在设计预算内，且不预读未被点击的条目
- [ ] 图片解压炸弹样例被拒绝并提示，内存不失控
- [ ] 断网验收通过；验收后确认未产生临时文件
- [ ] 原生 PNG/PDF/音视频预览不受影响；主应用仍不声明文档打开角色
- [ ] `./scripts/release-check.sh` 通过；新增解析路径有单元测试
- [ ] 项目内临时样例按约定删除

## 风险

| 风险 | 影响 | 应对 |
|---|---|---|
| ~~沙盒不允许读取子项内容~~ | — | **已验证通过**，不再是风险 |
| ~~libarchive 对加密 ZIP 条目行为不确定~~ | — | **已验证**：返回 `Passphrase required`，可按 `warnings` 提前拦截 |
| 大归档顺序扫描响应慢 | 右窗格等待久 | 超时上限 + LRU 缓存 + 明确的等待提示 |
| `PreviewSnapshot` 增字段影响现有 46 项测试 | 需同步补测试 | 新增字段保持默认值，实现时补图片与容器条目测试 |
| 右窗格引入后主视图布局回归 | 影响既有验收 | 非容器类型保持原有单视图路径不变 |
| 手改 `project.pbxproj` 出错 | 扩展 target 编译失败或漏编文件 | 改动后同时跑 `./scripts/test.sh`（SwiftPM 侧）与 `./scripts/build.sh`（Xcode 侧）交叉验证 |

## 待定决策

1. ~~右窗格复用范围~~：已定——**完全复用 `PreviewLoader`**，文件夹来源因此天然覆盖全部既有类型。
2. ~~归档内嵌套容器~~：已定为非目标（需要递归解压）。
3. **图片元信息**：右窗格是否需要额外显示像素尺寸、色彩空间等？
4. **导出条目**：是否提供"另存为"？这会写入磁盘，与"不落盘"约定冲突，当前列为非目标。
