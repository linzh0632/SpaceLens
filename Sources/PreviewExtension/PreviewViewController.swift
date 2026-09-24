import AppKit
import QuickLookUI
import OSLog

final class PreviewViewController: NSViewController, QLPreviewingController,
                                   NSOutlineViewDataSource, NSOutlineViewDelegate,
                                   NSTableViewDataSource, NSTableViewDelegate {
    private let fileIcon = NSImageView()
    private let heading = NSTextField(labelWithString: "SpaceLens")
    private let detail = NSTextField(labelWithString: "正在读取…")
    private let outline = NSOutlineView()
    private let tableScroll = NSScrollView()
    private let text = NSTextView()
    private let textScroll = NSScrollView()
    private let dataTable = NSTableView()
    private let dataScroll = NSScrollView()
    private let emptyState = NSTextField(wrappingLabelWithString: "")
    private let logger = Logger(subsystem: "io.github.linzh0632.SpaceLens", category: "preview")
    private var roots: [PreviewNode] = []
    private var tableData: PreviewSnapshot.TableData?
    private var generation = UUID()

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
        emptyState.alignment = .center
        emptyState.font = .systemFont(ofSize: 15)
        emptyState.textColor = .secondaryLabelColor
        emptyState.isHidden = true

        let separator = NSBox()
        separator.boxType = .separator
        for child in [fileIcon, heading, detail, separator, tableScroll, textScroll, dataScroll, emptyState] {
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
            tableScroll.leadingAnchor.constraint(equalTo: separator.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            tableScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            textScroll.leadingAnchor.constraint(equalTo: tableScroll.leadingAnchor),
            textScroll.trailingAnchor.constraint(equalTo: tableScroll.trailingAnchor),
            textScroll.topAnchor.constraint(equalTo: tableScroll.topAnchor),
            textScroll.bottomAnchor.constraint(equalTo: tableScroll.bottomAnchor),
            dataScroll.leadingAnchor.constraint(equalTo: tableScroll.leadingAnchor),
            dataScroll.trailingAnchor.constraint(equalTo: tableScroll.trailingAnchor),
            dataScroll.topAnchor.constraint(equalTo: tableScroll.topAnchor),
            dataScroll.bottomAnchor.constraint(equalTo: tableScroll.bottomAnchor),
            emptyState.centerXAnchor.constraint(equalTo: tableScroll.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: tableScroll.centerYAnchor),
            emptyState.widthAnchor.constraint(lessThanOrEqualTo: tableScroll.widthAnchor, constant: -80)
        ])
        view = root
        preferredContentSize = NSSize(width: 900, height: 620)
        showLoading()
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
        name.minWidth = 280
        name.width = 540
        let kind = NSTableColumn(identifier: .kindColumn)
        kind.title = "类型"
        kind.minWidth = 110
        kind.width = 150
        let size = NSTableColumn(identifier: .sizeColumn)
        size.title = "大小"
        size.minWidth = 90
        size.width = 120
        outline.addTableColumn(name)
        outline.addTableColumn(kind)
        outline.addTableColumn(size)
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

    func preparePreviewOfFile(at url: URL) async throws {
        _ = view
        let request = UUID()
        generation = request
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
        tableScroll.isHidden = true
        textScroll.isHidden = true
        dataScroll.isHidden = true
        emptyState.stringValue = "正在读取预览…"
        emptyState.isHidden = false
    }

    private func render(_ snapshot: PreviewSnapshot) {
        heading.stringValue = snapshot.title
        detail.stringValue = snapshot.summary
        emptyState.isHidden = true
        switch snapshot.contentKind {
        case .directory, .zip, .archive:
            configureOutlineColumns(name: "名称", kind: "类型", value: "大小")
            let isArchive = snapshot.contentKind == .zip || snapshot.contentKind == .archive
            fileIcon.image = NSImage(systemSymbolName: isArchive ? "doc.zipper" : "folder.fill",
                                     accessibilityDescription: nil)
            fileIcon.contentTintColor = isArchive ? .systemOrange : .systemBlue
            roots = PreviewNode.makeTree(from: snapshot.items)
            outline.reloadData()
            outline.expandItem(nil, expandChildren: true)
            tableScroll.isHidden = roots.isEmpty
            textScroll.isHidden = true
            dataScroll.isHidden = true
            if roots.isEmpty {
                emptyState.stringValue = isArchive ? "这个归档中没有可显示的条目。" : "这是一个空文件夹。"
                emptyState.isHidden = false
            }
        case .structured, .database:
            configureOutlineColumns(name: "键", kind: "类型", value: "值")
            let isDatabase = snapshot.contentKind == .database
            fileIcon.image = NSImage(systemSymbolName: isDatabase ? "cylinder.split.1x2.fill" : "curlybraces", accessibilityDescription: nil)
            fileIcon.contentTintColor = isDatabase ? .systemTeal : .systemPurple
            roots = PreviewNode.makeStructuredTree(from: snapshot.structuredItems)
            outline.reloadData()
            outline.expandItem(nil, expandChildren: true)
            tableScroll.isHidden = roots.isEmpty
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

    private func configureOutlineColumns(name: String, kind: String, value: String) {
        outline.tableColumns[0].title = name
        outline.tableColumns[1].title = kind
        outline.tableColumns[2].title = value
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
        tableScroll.isHidden = true
        textScroll.isHidden = true
        dataScroll.isHidden = true
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
    static let nameCell = Self("nameCell")
    static let kindCell = Self("kindCell")
    static let sizeCell = Self("sizeCell")
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
