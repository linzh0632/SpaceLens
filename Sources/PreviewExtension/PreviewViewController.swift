import AppKit
import QuickLookUI
import OSLog

final class PreviewViewController: NSViewController, QLPreviewingController,
                                   NSOutlineViewDataSource, NSOutlineViewDelegate,
                                   NSTableViewDataSource, NSTableViewDelegate,
                                   NSSplitViewDelegate {
    private let fileIcon = NSImageView()
    private let heading = NSTextField(labelWithString: "SpaceLens")
    private let detail = NSTextField(labelWithString: "正在读取…")
    private let outline = NSOutlineView()
    private let tableScroll = NSScrollView()
    private let split = NSSplitView()
    private let detailPane = DetailPreviewPane(frame: .zero)
    private let text = NSTextView()
    private let textScroll = NSScrollView()
    private let dataTable = NSTableView()
    private let dataScroll = NSScrollView()
    private let diagramImage = NSImageView()
    private let diagramScroll = NSScrollView()
    private let emptyState = NSTextField(wrappingLabelWithString: "")
    private let logger = Logger(subsystem: "io.github.linzh0632.SpaceLens", category: "preview")
    private var roots: [PreviewNode] = []
    private var tableData: PreviewSnapshot.TableData?
    private var generation = UUID()
    private var previewedURL: URL?
    private var containerKind: PreviewSnapshot.ContentKind?
    private var detailGeneration = UUID()
    private var didPositionSplit = false

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 620))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        fileIcon.imageScaling = .scaleProportionallyUpOrDown
        fileIcon.symbolConfiguration = .init(pointSize: 30, weight: .regular)
        fileIcon.contentTintColor = .systemBlue
        heading.font = .systemFont(ofSize: 25, weight: .bold)
        heading.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail

        configureOutline()
        configureTextView()
        configureDataTable()
        configureDiagram()
        emptyState.alignment = .center
        emptyState.font = .systemFont(ofSize: 15)
        emptyState.textColor = .secondaryLabelColor
        emptyState.isHidden = true

        let separator = NSBox()
        separator.boxType = .separator
        // The outline lives inside a split view so a clicked entry can be previewed on the right.
        // NSSplitView sizes its arranged subviews by frame, so those two opt out of Auto Layout
        // while every other view stays constraint driven.
        tableScroll.translatesAutoresizingMaskIntoConstraints = true
        detailPane.translatesAutoresizingMaskIntoConstraints = true
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        split.addArrangedSubview(tableScroll)
        split.addArrangedSubview(detailPane)
        split.isHidden = true

        for child in [fileIcon, heading, detail, separator, split, textScroll, dataScroll, diagramScroll, emptyState] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            fileIcon.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            fileIcon.topAnchor.constraint(equalTo: root.topAnchor, constant: 25),
            fileIcon.widthAnchor.constraint(equalToConstant: 46),
            fileIcon.heightAnchor.constraint(equalToConstant: 46),
            heading.leadingAnchor.constraint(equalTo: fileIcon.trailingAnchor, constant: 14),
            heading.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            heading.topAnchor.constraint(equalTo: fileIcon.topAnchor, constant: 1),
            detail.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            detail.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 5),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            separator.topAnchor.constraint(equalTo: fileIcon.bottomAnchor, constant: 20),
            split.leadingAnchor.constraint(equalTo: separator.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            split.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            split.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            textScroll.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            textScroll.trailingAnchor.constraint(equalTo: split.trailingAnchor),
            textScroll.topAnchor.constraint(equalTo: split.topAnchor),
            textScroll.bottomAnchor.constraint(equalTo: split.bottomAnchor),
            dataScroll.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            dataScroll.trailingAnchor.constraint(equalTo: split.trailingAnchor),
            dataScroll.topAnchor.constraint(equalTo: split.topAnchor),
            dataScroll.bottomAnchor.constraint(equalTo: split.bottomAnchor),
            diagramScroll.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            diagramScroll.trailingAnchor.constraint(equalTo: split.trailingAnchor),
            diagramScroll.topAnchor.constraint(equalTo: split.topAnchor),
            diagramScroll.bottomAnchor.constraint(equalTo: split.bottomAnchor),
            emptyState.centerXAnchor.constraint(equalTo: split.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: split.centerYAnchor),
            emptyState.widthAnchor.constraint(lessThanOrEqualTo: split.widthAnchor, constant: -80)
        ])
        view = root
        preferredContentSize = NSSize(width: 900, height: 620)
        showLoading()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // NSSplitView has no intrinsic divider position; place it once, on the first real layout.
        guard !didPositionSplit, split.frame.width > 0 else { return }
        didPositionSplit = true
        split.setPosition(min(420, max(320, split.frame.width * 0.55)), ofDividerAt: 0)
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        320
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(320, splitView.frame.width - 300)
    }

    private func configureOutline() {
        outline.dataSource = self
        outline.delegate = self
        outline.headerView = NSTableHeaderView()
        outline.rowHeight = 36
        outline.indentationPerLevel = 20
        outline.selectionHighlightStyle = .regular
        outline.usesAlternatingRowBackgroundColors = false
        outline.backgroundColor = .textBackgroundColor

        let name = NSTableColumn(identifier: .nameColumn)
        name.title = "名称"
        name.minWidth = 240
        name.width = 390
        let kind = NSTableColumn(identifier: .kindColumn)
        kind.title = "类型"
        kind.minWidth = 100
        kind.width = 130
        let size = NSTableColumn(identifier: .sizeColumn)
        size.title = "大小"
        size.minWidth = 80
        size.width = 100
        let modificationDate = NSTableColumn(identifier: .modificationDateColumn)
        modificationDate.title = "修改时间"
        modificationDate.minWidth = 160
        modificationDate.width = 190
        outline.addTableColumn(name)
        outline.addTableColumn(kind)
        outline.addTableColumn(size)
        outline.addTableColumn(modificationDate)
        outline.outlineTableColumn = name

        tableScroll.documentView = outline
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.borderType = .lineBorder
        tableScroll.wantsLayer = true
        tableScroll.layer?.cornerRadius = 10
        tableScroll.layer?.masksToBounds = true
    }

    private func configureTextView() {
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.textContainerInset = NSSize(width: 14, height: 14)
        text.backgroundColor = .textBackgroundColor
        textScroll.documentView = text
        textScroll.hasVerticalScroller = true
        textScroll.autohidesScrollers = true
        textScroll.borderType = .lineBorder
        textScroll.wantsLayer = true
        textScroll.layer?.cornerRadius = 10
        textScroll.layer?.masksToBounds = true
        textScroll.isHidden = true
    }

    private func configureDataTable() {
        dataTable.dataSource = self
        dataTable.delegate = self
        dataTable.headerView = NSTableHeaderView()
        dataTable.rowHeight = 30
        dataTable.usesAlternatingRowBackgroundColors = true
        dataTable.gridStyleMask = [.solidVerticalGridLineMask]
        dataScroll.documentView = dataTable
        dataScroll.hasVerticalScroller = true
        dataScroll.hasHorizontalScroller = true
        dataScroll.autohidesScrollers = true
        dataScroll.borderType = .lineBorder
        dataScroll.wantsLayer = true
        dataScroll.layer?.cornerRadius = 10
        dataScroll.layer?.masksToBounds = true
        dataScroll.isHidden = true
    }

    private func configureDiagram() {
        diagramImage.imageScaling = .scaleProportionallyUpOrDown
        diagramImage.imageAlignment = .alignCenter
        diagramScroll.documentView = diagramImage
        diagramScroll.hasVerticalScroller = true
        diagramScroll.hasHorizontalScroller = true
        diagramScroll.autohidesScrollers = true
        diagramScroll.borderType = .lineBorder
        diagramScroll.backgroundColor = .white
        diagramScroll.drawsBackground = true
        diagramScroll.isHidden = true
    }

    func preparePreviewOfFile(at url: URL) async throws {
        _ = view
        let request = UUID()
        generation = request
        previewedURL = url
        heading.stringValue = url.lastPathComponent
        showLoading()
        let worker = Task.detached(priority: .userInitiated) { try PreviewLoader.load(url) }
        do {
            let snapshot = try await withTaskCancellationHandler(operation: {
                try await worker.value
            }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard generation == request else { return }
            render(snapshot)
            logger.notice("SpaceLens preview rendered; truncated=\(snapshot.truncated)")
        } catch {
            guard generation == request else { return }
            if error is CancellationError { throw error }
            renderError(error)
            logger.error("SpaceLens preview failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func showLoading() {
        detail.stringValue = "SpaceLens · 正在读取…"
        fileIcon.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        roots = []
        outline.reloadData()
        split.isHidden = true
        containerKind = nil
        detailPane.showPlaceholder("选择左侧的文件以预览内容。")
        tableScroll.isHidden = true
        textScroll.isHidden = true
        dataScroll.isHidden = true
        diagramScroll.isHidden = true
        emptyState.stringValue = "正在读取预览…"
        emptyState.isHidden = false
    }

    private func render(_ snapshot: PreviewSnapshot) {
        heading.stringValue = snapshot.title
        detail.stringValue = snapshot.summary
        emptyState.isHidden = true
        diagramScroll.isHidden = true
        split.isHidden = true
        switch snapshot.contentKind {
        case .directory, .zip, .archive:
            configureOutlineColumns(name: "名称", kind: "类型", value: "大小", showsModificationDate: true)
            let isArchive = snapshot.contentKind == .zip || snapshot.contentKind == .archive
            fileIcon.image = NSImage(systemSymbolName: isArchive ? "doc.zipper" : "folder.fill",
                                     accessibilityDescription: nil)
            fileIcon.contentTintColor = isArchive ? .systemOrange : .systemBlue
            roots = PreviewNode.makeTree(from: snapshot.items)
            outline.reloadData()
            outline.expandItem(nil, expandChildren: true)
            outline.deselectAll(nil)
            containerKind = snapshot.contentKind
            split.isHidden = roots.isEmpty
            tableScroll.isHidden = roots.isEmpty
            detailPane.isHidden = false
            detailPane.showPlaceholder("选择左侧的文件以预览内容。")
            textScroll.isHidden = true
            dataScroll.isHidden = true
            if roots.isEmpty {
                emptyState.stringValue = isArchive ? "这个归档中没有可显示的条目。" : "这是一个空文件夹。"
                emptyState.isHidden = false
            }
        case .structured, .database:
            configureOutlineColumns(name: "键", kind: "类型", value: "值", showsModificationDate: false)
            let isDatabase = snapshot.contentKind == .database
            fileIcon.image = NSImage(systemSymbolName: isDatabase ? "cylinder.split.1x2.fill" : "curlybraces", accessibilityDescription: nil)
            fileIcon.contentTintColor = isDatabase ? .systemTeal : .systemPurple
            roots = PreviewNode.makeStructuredTree(from: snapshot.structuredItems)
            outline.reloadData()
            outline.expandItem(nil, expandChildren: true)
            // Structured values are not selectable entries, so the outline keeps the full width.
            containerKind = nil
            split.isHidden = roots.isEmpty
            tableScroll.isHidden = roots.isEmpty
            detailPane.isHidden = true
            textScroll.isHidden = true
            dataScroll.isHidden = true
            if roots.isEmpty {
                emptyState.stringValue = isDatabase ? "数据库中没有用户表。" : "没有可显示的结构。"
                emptyState.isHidden = false
            }
        case .table:
            fileIcon.image = NSImage(systemSymbolName: "tablecells.fill", accessibilityDescription: nil)
            fileIcon.contentTintColor = .systemGreen
            tableData = snapshot.table
            rebuildDataColumns()
            dataTable.reloadData()
            dataScroll.isHidden = false
            tableScroll.isHidden = true
            textScroll.isHidden = true
        case .diagram, .image:
            let isDiagram = snapshot.contentKind == .diagram
            fileIcon.image = NSImage(systemSymbolName: isDiagram
                ? "point.3.connected.trianglepath.dotted" : "photo.fill", accessibilityDescription: nil)
            fileIcon.contentTintColor = isDiagram ? .systemCyan : .systemPink
            let data = isDiagram ? snapshot.diagramSVG.map { Data($0.utf8) } : snapshot.imagePNGData
            guard let data, let image = NSImage(data: data) else {
                renderError(PreviewFailure.malformedText(isDiagram ? "图表 SVG 无法显示。" : "图片无法显示。"))
                return
            }
            diagramImage.image = image
            diagramImage.frame = NSRect(origin: .zero,
                size: NSSize(width: max(780, image.size.width), height: max(500, image.size.height)))
            diagramScroll.isHidden = false
            tableScroll.isHidden = true
            textScroll.isHidden = true
            dataScroll.isHidden = true
        case .text, .code, .markdown:
            fileIcon.image = NSImage(systemSymbolName: "doc.text.fill", accessibilityDescription: nil)
            fileIcon.contentTintColor = snapshot.contentKind == .markdown ? .systemIndigo : .systemBlue
            if snapshot.contentKind == .code { text.textStorage?.setAttributedString(highlightCode(snapshot.body)) }
            else if snapshot.contentKind == .markdown { text.textStorage?.setAttributedString(renderMarkdown(snapshot.body)) }
            else { text.string = snapshot.body; text.font = .monospacedSystemFont(ofSize: 13, weight: .regular) }
            textScroll.isHidden = false
            tableScroll.isHidden = true
            dataScroll.isHidden = true
        }
    }

    /// Loads the clicked entry into the right-hand pane. Only plain files are previewable; folder
    /// rows keep their expand/collapse behaviour and links are never followed.
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let kind = containerKind, let root = previewedURL else { return }
        let selected = outline.selectedRow
        guard selected >= 0,
              let node = outline.item(atRow: selected) as? PreviewNode,
              node.item?.kind == .file,
              let sourcePath = node.item?.sourcePath else {
            detailPane.showPlaceholder("选择左侧的文件以预览内容。")
            return
        }
        let source: EmbeddedPreviewLoader.Source
        switch kind {
        case .directory: source = .directoryChild(root: root, relativePath: sourcePath)
        case .zip, .archive: source = .archiveEntry(archive: root, path: sourcePath)
        default: return
        }
        let request = UUID()
        detailGeneration = request
        detailPane.showLoading(name: node.name)
        Task { @MainActor in
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try EmbeddedPreviewLoader.load(source)
                }.value
                guard self.detailGeneration == request else { return }
                self.detailPane.show(snapshot)
                self.logger.notice("SpaceLens detail preview rendered; kind=\(String(describing: snapshot.contentKind), privacy: .public)")
            } catch {
                guard self.detailGeneration == request else { return }
                if error is CancellationError { return }
                self.detailPane.showError(name: node.name, message: error.localizedDescription)
                self.logger.error("SpaceLens detail preview failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func configureOutlineColumns(name: String, kind: String, value: String,
                                         showsModificationDate: Bool) {
        outline.tableColumns[0].title = name
        outline.tableColumns[1].title = kind
        outline.tableColumns[2].title = value
        outline.tableColumns[3].isHidden = !showsModificationDate
    }

    private func rebuildDataColumns() {
        dataTable.tableColumns.forEach(dataTable.removeTableColumn)
        for (index, title) in (tableData?.columns ?? []).enumerated() {
            let column = NSTableColumn(identifier: .init("data-\(index)"))
            column.title = title
            column.width = 160
            column.minWidth = 80
            dataTable.addTableColumn(column)
        }
    }

    private func renderError(_ error: Error) {
        detail.stringValue = "SpaceLens · 无法读取"
        fileIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        fileIcon.contentTintColor = .systemOrange
        split.isHidden = true
        containerKind = nil
        tableScroll.isHidden = true
        textScroll.isHidden = true
        dataScroll.isHidden = true
        diagramScroll.isHidden = true
        emptyState.stringValue = error.localizedDescription
        emptyState.isHidden = false
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? PreviewNode)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? PreviewNode)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !(item as! PreviewNode).children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! PreviewNode
        switch tableColumn?.identifier {
        case .nameColumn:
            let cell = (outlineView.makeView(withIdentifier: .nameCell, owner: self) as? NameCell) ?? NameCell()
            cell.identifier = .nameCell
            cell.configure(node)
            return cell
        case .kindColumn:
            return labelCell(in: outlineView, identifier: .kindCell, value: node.kindLabel)
        case .sizeColumn:
            return labelCell(in: outlineView, identifier: .sizeCell,
                             value: node.valueLabel, alignment: node.structured == nil ? .right : .left)
        case .modificationDateColumn:
            return labelCell(in: outlineView, identifier: .modificationDateCell,
                             value: node.modificationDateLabel)
        default:
            return nil
        }
    }

    private func labelCell(in table: NSTableView, identifier: NSUserInterfaceItemIdentifier,
                           value: String, alignment: NSTextAlignment = .left) -> NSTableCellView {
        if let cell = table.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
           let label = cell.textField {
            label.stringValue = value
            label.alignment = alignment
            return cell
        }
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: value)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        label.alignment = alignment
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = label
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tableData?.rows.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let index = Int(tableColumn.identifier.rawValue.dropFirst(5)),
              let rows = tableData?.rows, row < rows.count else { return nil }
        let value = index < rows[row].count ? rows[row][index] : ""
        return labelCell(in: tableView, identifier: .init("dataCell-\(index)"), value: value)
    }
}

private final class PreviewNode: NSObject {
    let name: String
    var item: PreviewSnapshot.Item?
    var structured: PreviewSnapshot.StructuredItem?
    var children: [PreviewNode] = []

    init(name: String, item: PreviewSnapshot.Item? = nil) {
        self.name = name
        self.item = item
    }

    init(structured: PreviewSnapshot.StructuredItem) {
        self.name = structured.key
        self.structured = structured
    }

    var kindLabel: String {
        if let structured { return structured.type }
        guard let item else { return "文件夹" }
        switch item.kind {
        case .folder: return "文件夹"
        case .link: return "链接"
        case .package: return "包"
        case .file:
            let suffix = (name as NSString).pathExtension
            return suffix.isEmpty ? "文件" : suffix.uppercased()
        }
    }

    var valueLabel: String {
        if let structured { return structured.value ?? "—" }
        return item?.size.map(formatBytes) ?? "—"
    }

    var modificationDateLabel: String {
        guard structured == nil else { return "" }
        guard let date = item?.modificationDate else { return "—" }
        return Self.modificationDateFormatter.string(from: date)
    }

    private static let modificationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        let language = Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
        formatter.locale = Locale(identifier: language)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = false
        return formatter
    }()

    static func makeTree(from items: [PreviewSnapshot.Item]) -> [PreviewNode] {
        let root = PreviewNode(name: "")
        for item in items {
            let cleanPath = item.path.hasSuffix("/") ? String(item.path.dropLast()) : item.path
            let components = cleanPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !components.isEmpty else { continue }
            var parent = root
            for (index, component) in components.enumerated() {
                let isLeaf = index == components.count - 1
                if let existing = parent.children.first(where: { $0.name == component }) {
                    if isLeaf { existing.item = item }
                    parent = existing
                } else {
                    let node = PreviewNode(name: component, item: isLeaf ? item : nil)
                    parent.children.append(node)
                    parent = node
                }
            }
        }
        sort(root)
        return root.children
    }

    static func makeStructuredTree(from items: [PreviewSnapshot.StructuredItem]) -> [PreviewNode] {
        items.map { item in
            let node = PreviewNode(structured: item)
            node.children = makeStructuredTree(from: item.children)
            return node
        }
    }

    private static func sort(_ node: PreviewNode) {
        node.children.sort {
            let leftFolder = $0.item?.kind == .folder || $0.item == nil
            let rightFolder = $1.item?.kind == .folder || $1.item == nil
            if leftFolder != rightFolder { return leftFolder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        node.children.forEach(sort)
    }
}

private final class NameCell: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let warning = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.imageScaling = .scaleProportionallyUpOrDown
        warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        warning.contentTintColor = .systemOrange
        warning.isHidden = true
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingMiddle
        imageView = icon
        textField = label
        for child in [icon, label, warning] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            warning.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            warning.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            warning.centerYAnchor.constraint(equalTo: centerYAnchor),
            warning.widthAnchor.constraint(equalToConstant: 14),
            warning.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ node: PreviewNode) {
        label.stringValue = node.name
        if let structured = node.structured {
            icon.image = NSImage(systemSymbolName: structured.children.isEmpty ? "circle.fill" : "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)
            icon.contentTintColor = structured.children.isEmpty ? .tertiaryLabelColor : .systemPurple
            warning.isHidden = true
            return
        }
        let kind = node.item?.kind ?? .folder
        switch kind {
        case .folder:
            icon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            icon.contentTintColor = .systemBlue
        case .link:
            icon.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
            icon.contentTintColor = .systemTeal
        case .package:
            icon.image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)
            icon.contentTintColor = .systemIndigo
        case .file:
            icon.image = NSImage(systemSymbolName: iconName(for: node.name), accessibilityDescription: nil)
            icon.contentTintColor = iconColor(for: node.name)
        }
        warning.isHidden = node.item?.warnings.isEmpty != false
        warning.toolTip = node.item?.warnings.joined(separator: "、")
    }

    private func iconName(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "json", "yaml", "yml": return "curlybraces"
        case "md", "txt": return "doc.text.fill"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo.fill"
        case "pdf": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }

    private func iconColor(for name: String) -> NSColor {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift": return .systemOrange
        case "json", "yaml", "yml": return .systemPurple
        case "png", "jpg", "jpeg", "gif", "webp": return .systemPink
        case "pdf": return .systemRed
        default: return .secondaryLabelColor
        }
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let nameColumn = Self("name")
    static let kindColumn = Self("kind")
    static let sizeColumn = Self("size")
    static let modificationDateColumn = Self("modificationDate")
    static let nameCell = Self("nameCell")
    static let kindCell = Self("kindCell")
    static let sizeCell = Self("sizeCell")
    static let modificationDateCell = Self("modificationDateCell")
}

private func highlightCode(_ source: String) -> NSAttributedString {
    let full = NSRange(source.startIndex..<source.endIndex, in: source)
    let result = NSMutableAttributedString(string: source, attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor.labelColor
    ])
    let rules: [(String, NSColor)] = [
        (#"(?m)//.*$|#.*$|/\*[\s\S]*?\*/"#, .systemGray),
        (#"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'"#, .systemRed),
        (#"\b(?:true|false|null|nil|None|[0-9]+(?:\.[0-9]+)?)\b"#, .systemPurple),
        (#"\b(?:class|struct|enum|protocol|extension|func|let|var|if|else|for|while|return|throw|throws|try|catch|import|from|def|async|await|public|private|internal|static|const|function|new|switch|case|break|continue|SELECT|FROM|WHERE|INSERT|UPDATE|DELETE|CREATE|TABLE)\b"#, .systemBlue)
    ]
    for (pattern, color) in rules {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
        for match in expression.matches(in: source, range: full) {
            result.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
    return result
}

private func renderMarkdown(_ source: String) -> NSAttributedString {
    let result = NSMutableAttributedString()
    var inCodeBlock = false
    for rawLine in source.components(separatedBy: "\n") {
        if rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            inCodeBlock.toggle()
            continue
        }
        let line = rawLine + "\n"
        if inCodeBlock {
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = 14
            paragraph.firstLineHeadIndent = 14
            paragraph.paragraphSpacing = 1
            result.append(NSAttributedString(string: line, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.controlBackgroundColor,
                .paragraphStyle: paragraph
            ]))
            continue
        }
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        if let hashes = trimmed.prefix(while: { $0 == "#" }).count.nonzero,
           trimmed.dropFirst(hashes).first == " " {
            let title = String(trimmed.dropFirst(hashes + 1)) + "\n"
            let size = max(15, 28 - CGFloat(hashes - 1) * 3)
            result.append(NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ]))
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = 22
            paragraph.firstLineHeadIndent = 8
            result.append(NSAttributedString(string: "• " + String(trimmed.dropFirst(2)) + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 14), .paragraphStyle: paragraph
            ]))
        } else if trimmed.hasPrefix("> ") {
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = 18
            paragraph.firstLineHeadIndent = 18
            result.append(NSAttributedString(string: String(trimmed.dropFirst(2)) + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]))
        } else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = trimmed.isEmpty ? 7 : 3
            result.append(NSAttributedString(string: line, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]))
        }
    }
    return result
}

private extension Int {
    var nonzero: Int? { self == 0 ? nil : self }
}

/// Right-hand pane of a container preview. Renders one entry with a compact version of the same
/// view types the main preview uses. It never loads anything itself — the controller hands it an
/// already-loaded snapshot, so all reading limits stay in `EmbeddedPreviewLoader`.
private final class DetailPreviewPane: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate,
                                       NSTableViewDataSource, NSTableViewDelegate {
    private let titleLabel = NSTextField(labelWithString: "预览")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let textScroll = NSScrollView()
    private let imageView = NSImageView()
    private let imageScroll = NSScrollView()
    private let tableView = NSTableView()
    private let tableScroll = NSScrollView()
    private let outlineView = NSOutlineView()
    private let outlineScroll = NSScrollView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private var tableData: PreviewSnapshot.TableData?
    private var outlineRoots: [PreviewNode] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        showPlaceholder("选择左侧的文件以预览内容。")
    }

    required init?(coder: NSCoder) { nil }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.backgroundColor = .textBackgroundColor
        prepare(textScroll, document: textView)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        prepare(imageScroll, document: imageView)
        imageScroll.backgroundColor = .white
        imageScroll.drawsBackground = true

        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = true
        prepare(tableScroll, document: tableView)

        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.headerView = NSTableHeaderView()
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 14
        prepare(outlineScroll, document: outlineView)

        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.isHidden = true

        let divider = NSBox()
        divider.boxType = .separator

        for child in [titleLabel, subtitleLabel, divider, textScroll, imageScroll,
                      tableScroll, outlineScroll, messageLabel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        var constraints: [NSLayoutConstraint] = [
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            divider.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            divider.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40)
        ]
        for scroll in [textScroll, imageScroll, tableScroll, outlineScroll] {
            constraints.append(contentsOf: [
                scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                scroll.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
                scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
            ])
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func prepare(_ scroll: NSScrollView, document: NSView) {
        // A document view is frame sized: a zero-sized one leaves the scroll view showing nothing
        // but its border, which is how the pane looked before this was handled.
        document.frame = NSRect(x: 0, y: 0, width: 320, height: 320)
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .lineBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.layer?.masksToBounds = true
        scroll.isHidden = true
    }

    override func layout() {
        super.layout()
        // Keep frame-sized documents matched to the clip view. Height is left to AppKit so table
        // and outline views can still grow to fit their rows.
        let scrolled: [(NSScrollView, NSView)] = [(textScroll, textView), (tableScroll, tableView),
                                                  (outlineScroll, outlineView)]
        for (scroll, document) in scrolled {
            let width = scroll.contentSize.width
            if width > 1 { document.frame.size.width = width }
        }
    }

    /// Sizes a document view to the visible area right before its content is shown.
    private func reset(_ document: NSView, in scroll: NSScrollView) {
        let size = scroll.contentSize
        document.frame = NSRect(x: 0, y: 0, width: max(size.width, 1), height: max(size.height, 1))
    }

    /// Shows an image scaled down to the pane width, never enlarged past its natural size.
    private func showImage(_ image: NSImage) {
        var size = image.size
        let available = imageScroll.contentSize.width
        if size.width > 0, available > 1, size.width > available {
            let scale = available / size.width
            size = NSSize(width: floor(size.width * scale), height: floor(size.height * scale))
        }
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: size)
        imageScroll.isHidden = false
    }

    // MARK: - Content

    func showPlaceholder(_ text: String) {
        titleLabel.stringValue = "预览"
        subtitleLabel.stringValue = ""
        showMessage(text)
    }

    func showLoading(name: String) {
        titleLabel.stringValue = name
        subtitleLabel.stringValue = "SpaceLens · 正在读取…"
        showMessage("正在读取…")
    }

    func showError(name: String, message: String) {
        titleLabel.stringValue = name
        subtitleLabel.stringValue = "SpaceLens · 无法读取"
        showMessage(message)
    }

    func show(_ snapshot: PreviewSnapshot) {
        titleLabel.stringValue = snapshot.title
        subtitleLabel.stringValue = snapshot.summary
        hideContent()
        switch snapshot.contentKind {
        case .image:
            guard let data = snapshot.imagePNGData, let image = NSImage(data: data) else {
                showMessage("图片无法显示。")
                return
            }
            showImage(image)
        case .text, .code, .markdown:
            reset(textView, in: textScroll)
            if snapshot.contentKind == .code {
                textView.textStorage?.setAttributedString(highlightCode(snapshot.body))
            } else if snapshot.contentKind == .markdown {
                textView.textStorage?.setAttributedString(renderMarkdown(snapshot.body))
            } else {
                textView.string = snapshot.body
                textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            }
            textScroll.isHidden = false
        case .table:
            reset(tableView, in: tableScroll)
            tableData = snapshot.table
            rebuildTableColumns()
            tableView.reloadData()
            tableScroll.isHidden = false
        case .structured, .database:
            reset(outlineView, in: outlineScroll)
            outlineRoots = PreviewNode.makeStructuredTree(from: snapshot.structuredItems)
            configureOutlineColumns(isContainer: false)
            outlineView.reloadData()
            outlineView.expandItem(nil, expandChildren: true)
            if outlineRoots.isEmpty { showMessage("没有可显示的结构。") } else { outlineScroll.isHidden = false }
        case .diagram:
            guard let svg = snapshot.diagramSVG, let image = NSImage(data: Data(svg.utf8)) else {
                showMessage("图表无法显示。")
                return
            }
            showImage(image)
        case .directory, .zip, .archive:
            // A nested container is listed but not drillable; deeper nesting stays out of scope.
            reset(outlineView, in: outlineScroll)
            outlineRoots = PreviewNode.makeTree(from: snapshot.items)
            configureOutlineColumns(isContainer: true)
            outlineView.reloadData()
            outlineView.expandItem(nil, expandChildren: true)
            if outlineRoots.isEmpty { showMessage("这是空的容器。") } else { outlineScroll.isHidden = false }
        }
    }

    private func hideContent() {
        messageLabel.isHidden = true
        textScroll.isHidden = true
        imageScroll.isHidden = true
        tableScroll.isHidden = true
        outlineScroll.isHidden = true
    }

    private func showMessage(_ text: String) {
        textScroll.isHidden = true
        imageScroll.isHidden = true
        tableScroll.isHidden = true
        outlineScroll.isHidden = true
        messageLabel.stringValue = text
        messageLabel.isHidden = false
    }

    private func configureOutlineColumns(isContainer: Bool) {
        if outlineView.tableColumns.isEmpty {
            let name = NSTableColumn(identifier: .nameColumn)
            name.width = 200
            name.minWidth = 120
            let kind = NSTableColumn(identifier: .kindColumn)
            kind.width = 90
            kind.minWidth = 60
            let value = NSTableColumn(identifier: .sizeColumn)
            value.width = 80
            value.minWidth = 50
            let date = NSTableColumn(identifier: .modificationDateColumn)
            date.width = 140
            date.minWidth = 110
            outlineView.addTableColumn(name)
            outlineView.addTableColumn(kind)
            outlineView.addTableColumn(value)
            outlineView.addTableColumn(date)
            outlineView.outlineTableColumn = name
        }
        outlineView.tableColumns[0].title = isContainer ? "名称" : "键"
        outlineView.tableColumns[1].title = "类型"
        outlineView.tableColumns[2].title = isContainer ? "大小" : "值"
        outlineView.tableColumns[3].isHidden = !isContainer
    }

    private func rebuildTableColumns() {
        tableView.tableColumns.forEach(tableView.removeTableColumn)
        for (index, title) in (tableData?.columns ?? []).enumerated() {
            let column = NSTableColumn(identifier: .init("detail-\(index)"))
            column.title = title
            column.width = 130
            column.minWidth = 70
            tableView.addTableColumn(column)
        }
    }

    private func cell(_ value: String, identifier: NSUserInterfaceItemIdentifier) -> NSView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.identifier = identifier
        cell.textField = label
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    // MARK: - Outline data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? PreviewNode)?.children.count ?? outlineRoots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? PreviewNode)?.children[index] ?? outlineRoots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? PreviewNode)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        guard let node = item as? PreviewNode, let identifier = tableColumn?.identifier else { return nil }
        let value: String
        switch identifier {
        case .nameColumn: value = node.name
        case .kindColumn: value = node.kindLabel
        case .sizeColumn: value = node.valueLabel
        default: value = node.modificationDateLabel
        }
        return cell(value, identifier: identifier)
    }

    // MARK: - Table data source

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableData?.rows.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier,
              let index = tableView.tableColumns.firstIndex(where: { $0.identifier == identifier }),
              let rows = tableData?.rows, row < rows.count, index < rows[row].count else { return nil }
        return cell(rows[row][index], identifier: identifier)
    }
}
