import Foundation

/// Shows the first worksheet of an OOXML spreadsheet (`.xlsx` / `.xlsm`) as a table.
///
/// An OOXML package is a ZIP of XML parts, so this reuses the in-memory archive reader instead of
/// writing anything to disk. Only the parts needed for a read-only grid are opened: the workbook,
/// its relationships, the shared string table and one worksheet. Formulas are never evaluated — a
/// formula cell shows the value the file already cached — and macros are never read.
public enum SpreadsheetPreview {
    public static let extensions: Set<String> = ["xlsx", "xlsm"]

    static let maximumFileBytes = 64 * 1024 * 1024
    static let maximumPartBytes = 16 * 1024 * 1024
    static let maximumTotalPartBytes = 32 * 1024 * 1024
    static let maximumRows = 400
    static let maximumColumns = 60
    static let maximumSharedStrings = 20_000

    static let workbookPart = "xl/workbook.xml"
    static let relationshipsPart = "xl/_rels/workbook.xml.rels"
    static let sharedStringsPart = "xl/sharedStrings.xml"

    public static func load(_ url: URL) throws -> PreviewSnapshot {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= maximumFileBytes else {
            throw PreviewFailure.unsupportedData(L10n.text("文件超过 64 MiB 的安全读取上限。", "The file exceeds the 64 MiB safe read limit."))
        }

        // The worksheet part is only known after the workbook and its relationships are read, so the
        // package is opened twice: once for the fixed parts, once for the first sheet.
        let head = try ArchiveEntryReader.read(archive: url,
                                               wanted: [workbookPart, relationshipsPart, sharedStringsPart],
                                               perEntryLimit: maximumPartBytes,
                                               totalLimit: maximumTotalPartBytes)
        guard let workbookData = head[workbookPart] else {
            throw PreviewFailure.unsupportedData(L10n.text("这个文件不是有效的 XLSX 工作簿。", "This file is not a valid XLSX workbook."))
        }
        let sheets = try WorkbookParser.parse(workbookData)
        guard let firstSheet = sheets.first else {
            throw PreviewFailure.unsupportedData(L10n.text("工作簿里没有工作表。", "The workbook has no worksheets."))
        }
        let targets = head[relationshipsPart].map(RelationshipsParser.parse) ?? [:]
        guard let identifier = firstSheet.relationshipID,
              let target = targets[identifier],
              let sheetPart = partPath(for: target) else {
            throw PreviewFailure.unsupportedData(L10n.text("找不到第一个工作表的内容。", "The first worksheet could not be found."))
        }
        let sharedStrings = head[sharedStringsPart].map(SharedStringsParser.parse) ?? []

        let body = try ArchiveEntryReader.read(archive: url, wanted: [sheetPart],
                                               perEntryLimit: maximumPartBytes,
                                               totalLimit: maximumPartBytes)
        guard let sheetData = body[sheetPart] else {
            throw PreviewFailure.unsupportedData(L10n.text("找不到第一个工作表的内容。", "The first worksheet could not be found."))
        }
        let grid = WorksheetParser.parse(sheetData, sharedStrings: sharedStrings,
                                         maximumRows: maximumRows, maximumColumns: maximumColumns)
        guard !grid.rows.isEmpty else {
            throw PreviewFailure.unsupportedData(L10n.text("这张工作表没有可显示的内容。", "This worksheet has nothing to display."))
        }

        let width = max(1, min(grid.width, maximumColumns))
        let columns = CommonTextPreview.columnNames(grid.rows.first ?? [], width: width)
        let visibleRows = grid.rows.dropFirst().prefix(maximumRows).map { row -> [String] in
            (0..<width).map { $0 < row.count ? row[$0] : "" }
        }
        let totalRows = max(0, grid.rows.count - 1)
        let omitted = max(0, totalRows - visibleRows.count)
        var notes: [String] = []
        if sheets.count > 1 {
            notes.append(L10n.text("共 \(L10n.count(sheets.count, "个工作表", "sheet", "sheets"))",
                                   "\(L10n.count(sheets.count, "个工作表", "sheet", "sheets")) in total"))
        }
        if url.pathExtension.lowercased() == "xlsm" {
            notes.append(L10n.text("宏未读取", "macros ignored"))
        }
        if omitted > 0 {
            notes.append(L10n.text("另有 \(L10n.count(omitted, "行未显示", "more row not shown", "more rows not shown"))",
                                   "\(L10n.count(omitted, "行未显示", "more row not shown", "more rows not shown"))"))
        }
        let noteText = notes.isEmpty ? "" : " · " + notes.joined(separator: " · ")

        // The worksheet name comes from the file, so it is labelled as a name rather than translated.
        let sheetLabel = L10n.text("工作表「\(firstSheet.name)」", "sheet \"\(firstSheet.name)\"")
        return PreviewSnapshot(title: url.lastPathComponent,
            summary: "SpaceLens · XLSX · \(sheetLabel) · \(L10n.count(totalRows, "行", "row", "rows")) · \(L10n.count(columns.count, "列", "column", "columns"))\(noteText)",
            body: "", truncated: grid.truncated || omitted > 0, contentKind: .table,
            table: .init(columns: columns, rows: Array(visibleRows), omittedRowCount: omitted))
    }

    /// Resolves a relationship target to a package path. Targets are relative to `xl/` unless they
    /// start with a slash, and may contain `..` segments.
    static func partPath(for target: String) -> String? {
        var path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
        var parts: [String] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(String(component))
            }
        }
        path = parts.joined(separator: "/")
        return path.isEmpty ? nil : path
    }
}

// MARK: - xl/workbook.xml

private final class WorkbookParser: NSObject, XMLParserDelegate {
    private var sheets: [(name: String, relationshipID: String?)] = []

    static func parse(_ data: Data) throws -> [(name: String, relationshipID: String?)] {
        let delegate = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw PreviewFailure.unsupportedData(L10n.text("工作簿内容无法解析。", "The workbook could not be parsed."))
        }
        return delegate.sheets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard elementName == "sheet" else { return }
        let name = attributeDict["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sheets.append((name.isEmpty ? L10n.text("未命名工作表", "Untitled sheet") : name,
                       attributeDict["r:id"] ?? attributeDict["id"]))
    }
}

// MARK: - xl/_rels/workbook.xml.rels

private final class RelationshipsParser: NSObject, XMLParserDelegate {
    private var targets: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let delegate = RelationshipsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.targets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard elementName == "Relationship",
              let identifier = attributeDict["Id"],
              let target = attributeDict["Target"] else { return }
        targets[identifier] = target
    }
}

// MARK: - xl/sharedStrings.xml

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current: String?
    private var skipping = false

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return Array(delegate.strings.prefix(SpreadsheetPreview.maximumSharedStrings))
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "si" {
            current = ""
        } else if elementName == "rPh" {
            // Phonetic hints are metadata, not part of the displayed value.
            skipping = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard current != nil, !skipping else { return }
        current? += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "rPh" {
            skipping = false
        } else if elementName == "si", let value = current {
            strings.append(value)
            current = nil
        }
    }
}

// MARK: - xl/worksheets/sheetN.xml

private final class WorksheetParser: NSObject, XMLParserDelegate {
    struct Grid {
        var rows: [[String]] = []
        var width = 0
        var truncated = false
    }

    private let sharedStrings: [String]
    private let maximumRows: Int
    private let maximumColumns: Int
    private(set) var grid = Grid()

    private var row: [String] = []
    private var nextColumn = 0
    private var cellColumn = 0
    private var cellType: String?
    private var cellText: String?
    private var readingValue = false
    private var readingInlineText = false

    init(sharedStrings: [String], maximumRows: Int, maximumColumns: Int) {
        self.sharedStrings = sharedStrings
        self.maximumRows = maximumRows
        self.maximumColumns = maximumColumns
    }

    static func parse(_ data: Data, sharedStrings: [String],
                      maximumRows: Int, maximumColumns: Int) -> Grid {
        let delegate = WorksheetParser(sharedStrings: sharedStrings,
                                       maximumRows: maximumRows, maximumColumns: maximumColumns)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        // A worksheet larger than the read limit is cut mid-document; keep the rows parsed so far
        // instead of failing the whole preview.
        if !parser.parse(), !delegate.grid.rows.isEmpty { delegate.grid.truncated = true }
        return delegate.grid
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        switch elementName {
        case "row":
            row = []
            nextColumn = 0
        case "c":
            let reference = attributeDict["r"] ?? ""
            cellColumn = Self.columnIndex(from: reference) ?? nextColumn
            cellType = attributeDict["t"]
            cellText = nil
        case "v":
            readingValue = true
            cellText = ""
        case "t" where cellType == "inlineStr":
            readingInlineText = true
            cellText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard readingValue || readingInlineText else { return }
        cellText? += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "v":
            readingValue = false
        case "t":
            readingInlineText = false
        case "c":
            append(resolvedValue(), at: cellColumn)
            nextColumn = cellColumn + 1
            cellType = nil
            cellText = nil
        case "row":
            store()
        default:
            break
        }
    }

    private func resolvedValue() -> String {
        let value = cellText ?? ""
        switch cellType {
        case "s":
            guard let index = Int(value), index >= 0, index < sharedStrings.count else { return value }
            return sharedStrings[index]
        case "b":
            return value == "1" ? "TRUE" : "FALSE"
        default:
            return value
        }
    }

    private func append(_ value: String, at column: Int) {
        guard column >= 0 else { return }
        guard column < maximumColumns else {
            grid.truncated = true
            return
        }
        while row.count < column { row.append("") }
        if row.count == column { row.append(value) } else { row[column] = value }
    }

    private func store() {
        while let last = row.last, last.isEmpty { row.removeLast() }
        guard !row.isEmpty else { return }
        grid.width = max(grid.width, row.count)
        guard grid.rows.count < maximumRows else {
            grid.truncated = true
            return
        }
        grid.rows.append(row)
    }

    /// `"AB12"` → column index 27.
    private static func columnIndex(from reference: String) -> Int? {
        var index = 0
        var found = false
        for character in reference {
            guard let ascii = character.asciiValue, ascii >= 65, ascii <= 90 else { break }
            index = index * 26 + Int(ascii - 64)
            found = true
        }
        return found ? index - 1 : nil
    }
}
