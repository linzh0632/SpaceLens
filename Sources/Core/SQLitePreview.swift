import Foundation

enum SQLitePreview {
    private static let maximumTables = 50
    private static let maximumColumns = 100
    private static let maximumRows = 100
    private static let maximumCellCharacters = 500

    static func load(_ url: URL) throws -> PreviewSnapshot {
        var database: OpaquePointer?
        let result = url.path.withCString {
            sqlite3_open_v2($0, &database, sqliteOpenReadonly | sqliteOpenNoMutex, nil)
        }
        guard result == sqliteOK, let database else {
            let detail = database.map(errorMessage) ?? L10n.text("无法打开数据库", "Cannot open the database")
            if let database { _ = sqlite3_close_v2(database) }
            throw PreviewFailure.damagedDatabase(detail)
        }
        defer { _ = sqlite3_close_v2(database) }
        _ = sqlite3_busy_timeout(database, 50)

        let tableRows = try query(database,
            sql: "SELECT name, sql FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name LIMIT \(maximumTables + 1)")
        let truncatedTables = tableRows.count > maximumTables
        let visibleTables = tableRows.prefix(maximumTables)
        var roots: [PreviewSnapshot.StructuredItem] = []
        var sampledRows = 0
        var truncated = truncatedTables

        for table in visibleTables {
            try Task.checkCancellation()
            guard let name = table.first?.text, !name.isEmpty else { continue }
            let definition = table.count > 1 ? table[1].text ?? "" : ""
            let virtual = definition.uppercased().contains("CREATE VIRTUAL TABLE")
            let quoted = quoteIdentifier(name)
            let columns = try query(database, sql: "PRAGMA table_info(\(quoted))")
            var columnItems: [PreviewSnapshot.StructuredItem] = []
            for column in columns.prefix(maximumColumns) {
                let columnName = column[safe: 1]?.text ?? L10n.text("<未命名>", "<unnamed>")
                let declaredType = column[safe: 2]?.text?.isEmpty == false ? column[2].text! : L10n.text("未声明", "Undeclared")
                var flags: [String] = []
                if column[safe: 3]?.integer == 1 { flags.append("NOT NULL") }
                if column[safe: 5]?.integer ?? 0 > 0 { flags.append("PRIMARY KEY") }
                if let defaultValue = column[safe: 4]?.text { flags.append(L10n.text("默认 \(clipped(defaultValue))", "Default \(clipped(defaultValue))")) }
                columnItems.append(.init(key: columnName, type: declaredType,
                                         value: flags.isEmpty ? nil : flags.joined(separator: " · ")))
            }
            if columns.count > maximumColumns { truncated = true }

            var tableChildren: [PreviewSnapshot.StructuredItem] = [
                .init(key: L10n.text("结构", "Structure"), type: L10n.text("\(columns.count) 列", "\(columns.count) columns"), children: columnItems)
            ]
            var rowItems: [PreviewSnapshot.StructuredItem] = []
            var rowTruncated = false
            if virtual {
                tableChildren.append(.init(key: L10n.text("数据", "Data"), type: L10n.text("虚拟表", "Virtual table"), value: L10n.text("为避免加载扩展模块，不读取样本", "Samples are not read, to avoid loading extension modules")))
            } else {
                let rows = try query(database, sql: "SELECT * FROM \(quoted) LIMIT \(maximumRows + 1)")
                rowTruncated = rows.count > maximumRows
                for (index, row) in rows.prefix(maximumRows).enumerated() {
                    let cells = row.enumerated().map { offset, cell in
                        let name = columns[safe: offset]?[safe: 1]?.text ?? L10n.text("列 \(offset + 1)", "Column \(offset + 1)")
                        return PreviewSnapshot.StructuredItem(key: name, type: cell.typeName,
                                                              value: cell.displayValue)
                    }
                    rowItems.append(.init(key: "#\(index + 1)", type: L10n.text("记录", "Record"), children: cells))
                }
                sampledRows += rowItems.count
                truncated = truncated || rowTruncated
                tableChildren.append(.init(key: L10n.text("数据", "Data"), type: L10n.text("\(rowItems.count) 行", "\(rowItems.count) rows") + (rowTruncated ? L10n.text("（仅显示前 \(maximumRows) 行）", " (showing the first \(maximumRows) rows)") : ""),
                                           children: rowItems))
            }
            let tableType = virtual ? L10n.text("虚拟表", "Virtual table") : L10n.text("表", "Table")
            roots.append(.init(key: name, type: tableType,
                               value: L10n.text("\(columns.count) 列 · \(rowItems.count) 行样本", "\(columns.count) columns · \(rowItems.count) sampled rows"),
                               children: tableChildren))
        }

        return PreviewSnapshot(
            title: url.lastPathComponent,
            summary: L10n.text("SpaceLens · SQLite · \(visibleTables.count) 个表 · \(sampledRows) 行样本", "SpaceLens · SQLite · \(visibleTables.count) tables · \(sampledRows) sampled rows") + (truncated ? L10n.text(" · 已按安全上限截断", " · truncated at the safety limit") : ""),
            body: "",
            truncated: truncated,
            contentKind: .database,
            structuredItems: roots,
            language: "SQLite"
        )
    }

    private static func query(_ database: OpaquePointer, sql: String) throws -> [[Cell]] {
        var statement: OpaquePointer?
        let prepared = sql.withCString { sqlite3_prepare_v2(database, $0, -1, &statement, nil) }
        guard prepared == sqliteOK, let statement else { throw PreviewFailure.damagedDatabase(errorMessage(database)) }
        defer { _ = sqlite3_finalize(statement) }
        var rows: [[Cell]] = []
        while true {
            try Task.checkCancellation()
            let status = sqlite3_step(statement)
            if status == sqliteDone { break }
            guard status == sqliteRow else { throw PreviewFailure.damagedDatabase(errorMessage(database)) }
            let count = min(Int(sqlite3_column_count(statement)), maximumColumns)
            rows.append((0..<count).map { cell(statement, Int32($0)) })
        }
        return rows
    }

    private static func cell(_ statement: OpaquePointer, _ index: Int32) -> Cell {
        switch sqlite3_column_type(statement, index) {
        case sqliteInteger:
            return .init(typeName: L10n.text("整数", "Integer"), displayValue: String(sqlite3_column_int64(statement, index)),
                         integer: sqlite3_column_int64(statement, index))
        case sqliteFloat:
            return .init(typeName: L10n.text("浮点数", "Float"), displayValue: String(sqlite3_column_double(statement, index)))
        case sqliteText:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard let pointer = sqlite3_column_text(statement, index) else { return .init(typeName: L10n.text("文本", "Text"), displayValue: "") }
            let value = String(decoding: UnsafeBufferPointer(start: pointer, count: count), as: UTF8.self)
            return .init(typeName: L10n.text("文本", "Text"), displayValue: clipped(value), text: value)
        case sqliteBlob:
            return .init(typeName: "BLOB", displayValue: L10n.text("\(sqlite3_column_bytes(statement, index)) 字节", "\(sqlite3_column_bytes(statement, index)) bytes"))
        default:
            return .init(typeName: "NULL", displayValue: "NULL")
        }
    }

    private static func quoteIdentifier(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func errorMessage(_ database: OpaquePointer) -> String {
        sqlite3_errmsg(database).map(String.init(cString:)) ?? L10n.text("SQLite 读取失败", "SQLite read failed")
    }

    private static func clipped(_ value: String) -> String {
        value.count <= maximumCellCharacters ? value : String(value.prefix(maximumCellCharacters)) + "…"
    }

    private struct Cell {
        let typeName: String
        let displayValue: String
        var text: String? = nil
        var integer: Int64? = nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private let sqliteOK: Int32 = 0
private let sqliteRow: Int32 = 100
private let sqliteDone: Int32 = 101
private let sqliteInteger: Int32 = 1
private let sqliteFloat: Int32 = 2
private let sqliteText: Int32 = 3
private let sqliteBlob: Int32 = 4
private let sqliteOpenReadonly: Int32 = 0x0000_0001
private let sqliteOpenNoMutex: Int32 = 0x0000_8000

@_silgen_name("sqlite3_open_v2") private func sqlite3_open_v2(_ filename: UnsafePointer<CChar>?, _ database: UnsafeMutablePointer<OpaquePointer?>?, _ flags: Int32, _ vfs: UnsafePointer<CChar>?) -> Int32
@_silgen_name("sqlite3_close_v2") private func sqlite3_close_v2(_ database: OpaquePointer?) -> Int32
@_silgen_name("sqlite3_busy_timeout") private func sqlite3_busy_timeout(_ database: OpaquePointer?, _ milliseconds: Int32) -> Int32
@_silgen_name("sqlite3_prepare_v2") private func sqlite3_prepare_v2(_ database: OpaquePointer?, _ sql: UnsafePointer<CChar>?, _ bytes: Int32, _ statement: UnsafeMutablePointer<OpaquePointer?>?, _ tail: UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32
@_silgen_name("sqlite3_step") private func sqlite3_step(_ statement: OpaquePointer?) -> Int32
@_silgen_name("sqlite3_finalize") private func sqlite3_finalize(_ statement: OpaquePointer?) -> Int32
@_silgen_name("sqlite3_column_count") private func sqlite3_column_count(_ statement: OpaquePointer?) -> Int32
@_silgen_name("sqlite3_column_type") private func sqlite3_column_type(_ statement: OpaquePointer?, _ index: Int32) -> Int32
@_silgen_name("sqlite3_column_text") private func sqlite3_column_text(_ statement: OpaquePointer?, _ index: Int32) -> UnsafePointer<UInt8>?
@_silgen_name("sqlite3_column_bytes") private func sqlite3_column_bytes(_ statement: OpaquePointer?, _ index: Int32) -> Int32
@_silgen_name("sqlite3_column_int64") private func sqlite3_column_int64(_ statement: OpaquePointer?, _ index: Int32) -> Int64
@_silgen_name("sqlite3_column_double") private func sqlite3_column_double(_ statement: OpaquePointer?, _ index: Int32) -> Double
@_silgen_name("sqlite3_errmsg") private func sqlite3_errmsg(_ database: OpaquePointer?) -> UnsafePointer<CChar>?
