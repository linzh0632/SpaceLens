import Foundation

public struct PreviewSnapshot: Sendable {
    public enum ContentKind: Sendable, Equatable {
        case text
        case code
        case markdown
        case table
        case structured
        case database
        case diagram
        case directory
        case zip
        case archive
        case image
    }

    public struct TableData: Sendable, Equatable {
        public let columns: [String]
        public let rows: [[String]]
        public let omittedRowCount: Int

        public init(columns: [String], rows: [[String]], omittedRowCount: Int = 0) {
            self.columns = columns
            self.rows = rows
            self.omittedRowCount = omittedRowCount
        }
    }

    public struct StructuredItem: Sendable, Equatable {
        public let key: String
        public let type: String
        public let value: String?
        public let children: [StructuredItem]

        public init(key: String, type: String, value: String? = nil,
                    children: [StructuredItem] = []) {
            self.key = key
            self.type = type
            self.value = value
            self.children = children
        }
    }

    public struct Item: Sendable, Equatable {
        public enum Kind: String, Sendable {
            case file
            case folder
            case link
            case package
        }

        public let path: String
        /// Locates the entry inside its container (folder or archive). Unlike `path` it is not
        /// display-escaped, so it can resolve the real child URL or the archive entry name.
        public let sourcePath: String?
        public let kind: Kind
        public let size: Int64?
        public let compressedSize: Int64?
        public let modificationDate: Date?
        public let compression: String?
        public let warnings: [String]

        public init(path: String, sourcePath: String? = nil, kind: Kind, size: Int64? = nil,
                    compressedSize: Int64? = nil, modificationDate: Date? = nil,
                    compression: String? = nil, warnings: [String] = []) {
            self.path = path
            self.sourcePath = sourcePath
            self.kind = kind
            self.size = size
            self.compressedSize = compressedSize
            self.modificationDate = modificationDate
            self.compression = compression
            self.warnings = warnings
        }
    }

    public let title: String
    public let summary: String
    public let body: String
    public let truncated: Bool
    public let contentKind: ContentKind
    public let items: [Item]
    public let table: TableData?
    public let structuredItems: [StructuredItem]
    public let language: String?
    public let diagramSVG: String?
    /// PNG-encoded thumbnail for `.image` snapshots. Kept as `Data` so the snapshot remains
    /// `Sendable` and no `CGImage` crosses a concurrency domain.
    public let imagePNGData: Data?

    public init(title: String, summary: String, body: String, truncated: Bool,
                contentKind: ContentKind = .text, items: [Item] = [],
                table: TableData? = nil, structuredItems: [StructuredItem] = [],
                language: String? = nil, diagramSVG: String? = nil,
                imagePNGData: Data? = nil) {
        self.title = title
        self.summary = summary
        self.body = body
        self.truncated = truncated
        self.contentKind = contentKind
        self.items = items
        self.table = table
        self.structuredItems = structuredItems
        self.language = language
        self.diagramSVG = diagramSVG
        self.imagePNGData = imagePNGData
    }
}

public enum PreviewFailure: LocalizedError, Equatable {
    case unsupported
    case invalidText
    case malformedText(String)
    case damagedArchive(String)
    case unsupportedArchive(String)
    case damagedDatabase(String)
    case damagedData(String)
    case unsupportedData(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported: return "SpaceLens 暂不支持这种文件。"
        case .invalidText: return "文本编码无法识别；当前支持 UTF-8 和带 BOM 的 UTF-16。"
        case .malformedText(let detail): return detail
        case .damagedArchive(let detail): return "归档文件已损坏或不完整：\(detail)"
        case .unsupportedArchive(let detail): return "暂不支持这个归档：\(detail)"
        case .damagedDatabase(let detail): return "SQLite 数据库无法读取：\(detail)"
        case .damagedData(let detail): return "数据文件已损坏或不完整：\(detail)"
        case .unsupportedData(let detail): return "暂不支持这个数据文件：\(detail)"
        }
    }
}

public enum PreviewLoader {
    public static let maximumEntries = 10_000
    public static let maximumDepth = 10
    public static let maximumBytes = 64 * 1024
    public static let maximumTextBytes = 5 * 1024 * 1024

    public static func load(_ url: URL) throws -> PreviewSnapshot {
        try load(url, entryLimit: maximumEntries, depthLimit: maximumDepth)
    }

    static func load(_ url: URL, entryLimit: Int, depthLimit: Int) throws -> PreviewSnapshot {
        precondition(entryLimit > 0 && depthLimit > 0)
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
            .isPackageKey, .fileSizeKey, .contentModificationDateKey
        ]
        let values = try url.resourceValues(forKeys: keys)
        if values.isDirectory == true && values.isSymbolicLink != true {
            return try DirectoryPreview.load(url, keys: keys, entryLimit: entryLimit, depthLimit: depthLimit)
        }
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw PreviewFailure.unsupported }
        switch url.pathExtension.lowercased() {
        case "zip": return try ZipPreview.load(url, entryLimit: entryLimit)
        case "spacelens": return try loadAcceptanceFile(url)
        case "plist": return try PropertyListPreview.load(url)
        case "db", "sqlite", "sqlite3": return try SQLitePreview.load(url)
        case let ext where ColumnarPreview.extensions.contains(ext): return try ColumnarPreview.load(url)
        case let ext where ArchivePreview.extensions.contains(ext):
            return try ArchivePreview.load(url, entryLimit: entryLimit)
        case let ext where ImagePreview.extensions.contains(ext):
            return try ImagePreview.load(url)
        default: return try CommonTextPreview.load(url, byteLimit: maximumTextBytes)
        }
    }

    private static func loadAcceptanceFile(_ url: URL) throws -> PreviewSnapshot {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        try Task.checkCancellation()
        let truncated = data.count > maximumBytes
        let prefix = Data(data.prefix(maximumBytes))
        var text = String(data: prefix, encoding: .utf8)
        if truncated && text == nil {
            for count in 1...3 {
                text = String(data: prefix.dropLast(count), encoding: .utf8)
                if text != nil { break }
            }
        }
        guard let text else { throw PreviewFailure.invalidText }
        return PreviewSnapshot(title: url.lastPathComponent,
            summary: "SpaceLens · 验收文件\(truncated ? " · 仅显示前 64 KiB" : "")",
            body: text, truncated: truncated, contentKind: .text)
    }
}

private enum DirectoryPreview {
    struct Row {
        let path: String
        let sourcePath: String
        let depth: Int
        let kind: String
        let size: Int64?
        let date: Date?
    }

    static func load(_ url: URL, keys: Set<URLResourceKey>, entryLimit: Int, depthLimit: Int) throws -> PreviewSnapshot {
        // FileManager may return /private/var descendants for a /var root. Resolve only
        // the already-validated root so relative paths remain stable without following
        // any symlinks found inside the folder.
        let enumerationRoot = url.standardizedFileURL.resolvingSymlinksInPath()
        var enumerationError: Error?
        guard let iterator = FileManager.default.enumerator(at: enumerationRoot,
            includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants],
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw CocoaError(.fileReadNoPermission)
        }
        var rows: [Row] = []
        var truncatedByCount = false
        var truncatedByDepth = false
        var fileCount = 0
        var folderCount = 0
        var totalBytes: Int64 = 0

        while let child = iterator.nextObject() as? URL {
            try Task.checkCancellation()
            if rows.count == entryLimit { truncatedByCount = true; break }
            // `level` is relative to the enumerated root and remains correct even
            // when macOS rewrites /var descendants as /private/var URLs.
            let relativeComponents = child.pathComponents.suffix(iterator.level)
            let relative = relativeComponents.joined(separator: "/")
            let depth = max(1, relativeComponents.count)
            let metadata = try child.resourceValues(forKeys: keys)
            let isLink = metadata.isSymbolicLink == true
            let isPackage = metadata.isPackage == true
            let isDirectory = metadata.isDirectory == true && !isLink && !isPackage
            if depth > depthLimit {
                truncatedByDepth = true; iterator.skipDescendants(); continue
            }
            if depth == depthLimit && isDirectory {
                truncatedByDepth = true; iterator.skipDescendants()
            }
            let kind: String
            let size: Int64?
            if isLink { kind = "链接"; size = nil }
            else if isPackage { kind = "包"; size = nil; fileCount += 1 }
            else if isDirectory { kind = "文件夹"; size = nil; folderCount += 1 }
            else {
                kind = "文件"; size = metadata.fileSize.map(Int64.init)
                totalBytes += size ?? 0; fileCount += 1
            }
            rows.append(Row(path: escape(relative), sourcePath: relative, depth: depth, kind: kind,
                size: size, date: metadata.contentModificationDate))
        }
        if let error = enumerationError { throw error }
        rows.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        let truncated = truncatedByCount || truncatedByDepth
        var limits: [String] = []
        if truncatedByCount { limits.append("最多 \(entryLimit) 项") }
        if truncatedByDepth { limits.append("最多 \(depthLimit) 层") }
        let suffix = limits.isEmpty ? "" : " · 已限制：" + limits.joined(separator: "、")
        let items = rows.map { row in
            PreviewSnapshot.Item(path: row.path, sourcePath: row.sourcePath, kind: itemKind(row.kind),
                                 size: row.size, modificationDate: row.date)
        }
        return PreviewSnapshot(title: url.lastPathComponent,
            summary: "SpaceLens · 文件夹 · \(folderCount) 个文件夹 · \(fileCount) 个文件 · \(formatBytes(totalBytes))\(suffix)",
            body: rows.isEmpty ? "这是一个空文件夹。" : rows.map(render).joined(separator: "\n"),
            truncated: truncated, contentKind: .directory, items: items)
    }

    private static func render(_ row: Row) -> String {
        let leaf = row.path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? row.path
        let indentation = String(repeating: "  ", count: max(0, row.depth - 1))
        let size = row.size.map { " · \(formatBytes($0))" } ?? ""
        let date = row.date.map { " · \(formatDate($0))" } ?? ""
        return "\(indentation)[\(row.kind)] \(leaf)\(size)\(date)"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func itemKind(_ value: String) -> PreviewSnapshot.Item.Kind {
        switch value {
        case "文件夹": return .folder
        case "链接": return .link
        case "包": return .package
        default: return .file
        }
    }
}

func formatBytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

func formatDate(_ value: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
    return formatter.string(from: value).replacingOccurrences(of: "T", with: " ")
}
