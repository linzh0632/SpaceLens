import Foundation
import CoreFoundation

enum CommonTextPreview {
    private struct ParsedTable {
        let rows: [[String]]
        let totalRowCount: Int
    }
    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let tableExtensions: Set<String> = ["csv", "tsv"]
    private static let structuredExtensions: Set<String> = ["json", "jsonl", "ndjson"]
    private static let codeExtensions: Set<String> = [
        "c", "cc", "cpp", "cxx", "h", "hpp", "m", "mm", "swift", "py", "rb", "go", "rs",
        "java", "kt", "kts", "js", "jsx", "ts", "tsx", "css", "scss", "sass", "less", "html",
        "htm", "xml", "sh", "bash", "zsh", "fish", "ps1", "lua", "php", "r", "dart", "scala",
        "sql", "graphql", "gql", "yaml", "yml", "toml", "ini", "conf", "config", "env", "diff", "patch"
    ]
    private static let plainExtensions: Set<String> = ["txt", "text", "log"]
    private static let specialNames: Set<String> = [
        "dockerfile", "makefile", "gemfile", "podfile", "rakefile", "license", "readme", ".gitignore", ".gitattributes", ".editorconfig"
    ]
    private static let maximumRows = 1_000
    private static let maximumColumns = 100
    private static let maximumJSONNodes = 10_000
    private static let maximumJSONDepth = 50

    static func load(_ url: URL, byteLimit: Int) throws -> PreviewSnapshot {
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent.lowercased()
        guard markdownExtensions.contains(ext) || tableExtensions.contains(ext) ||
                structuredExtensions.contains(ext) || codeExtensions.contains(ext) ||
                plainExtensions.contains(ext) || specialNames.contains(filename) else {
            throw PreviewFailure.unsupported
        }
        let (source, truncated) = try readText(url, byteLimit: byteLimit)
        try Task.checkCancellation()
        let suffix = truncated ? " · 仅显示前 \(formatBytes(Int64(byteLimit)))" : ""
        if markdownExtensions.contains(ext) {
            return PreviewSnapshot(title: url.lastPathComponent,
                summary: "SpaceLens · Markdown · \(lineCount(source)) 行\(suffix)", body: source,
                truncated: truncated, contentKind: .markdown, language: "Markdown")
        }
        if tableExtensions.contains(ext) {
            return try loadTable(url, source: source, delimiter: ext == "tsv" ? "\t" : ",", truncated: truncated, suffix: suffix)
        }
        if structuredExtensions.contains(ext) {
            return try loadStructured(url, source: source, lineDelimited: ext != "json", truncated: truncated, suffix: suffix)
        }
        let language = languageName(extension: ext, filename: filename)
        let kind: PreviewSnapshot.ContentKind = codeExtensions.contains(ext) || specialNames.contains(filename) ? .code : .text
        return PreviewSnapshot(title: url.lastPathComponent,
            summary: "SpaceLens · \(kind == .code ? language : "文本") · \(lineCount(source)) 行\(suffix)",
            body: source, truncated: truncated, contentKind: kind, language: language)
    }

    private static func readText(_ url: URL, byteLimit: Int) throws -> (String, Bool) {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: byteLimit + 1) ?? Data()
        let truncated = data.count > byteLimit
        var prefix = Data(data.prefix(byteLimit))
        let text: String?
        if prefix.starts(with: [0xff, 0xfe]) {
            if prefix.count.isMultiple(of: 2) == false { prefix.removeLast() }
            text = String(data: prefix.dropFirst(2), encoding: .utf16LittleEndian)
        } else if prefix.starts(with: [0xfe, 0xff]) {
            if prefix.count.isMultiple(of: 2) == false { prefix.removeLast() }
            text = String(data: prefix.dropFirst(2), encoding: .utf16BigEndian)
        } else {
            var candidate = String(data: prefix, encoding: .utf8)
            if truncated && candidate == nil {
                for count in 1...min(3, prefix.count) {
                    candidate = String(data: prefix.dropLast(count), encoding: .utf8)
                    if candidate != nil { break }
                }
            }
            text = candidate
        }
        guard let text, !text.contains("\0") else { throw PreviewFailure.invalidText }
        return (text, truncated)
    }

    private static func loadTable(_ url: URL, source: String, delimiter: Character,
                                  truncated: Bool, suffix: String) throws -> PreviewSnapshot {
        let parsed = try parseDelimited(source, delimiter: delimiter)
        let rawHeader = parsed.rows.first ?? []
        let width = min(max(1, rawHeader.count), maximumColumns)
        var used: [String: Int] = [:]
        let columns = (0..<width).map { index -> String in
            let base = index < rawHeader.count && !rawHeader[index].isEmpty ? rawHeader[index] : "列 \(index + 1)"
            let occurrence = (used[base] ?? 0) + 1
            used[base] = occurrence
            return occurrence == 1 ? base : "\(base) (\(occurrence))"
        }
        let allRows = parsed.rows.dropFirst()
        let visibleRows = allRows.prefix(maximumRows).map { row in
            (0..<width).map { $0 < row.count ? row[$0] : "" }
        }
        let totalDataRows = max(0, parsed.totalRowCount - 1)
        let omitted = max(0, totalDataRows - visibleRows.count)
        let limits = omitted > 0 ? " · 另有 \(omitted) 行未显示" : ""
        let columnLimit = rawHeader.count > maximumColumns ? " · 仅显示前 \(maximumColumns) 列" : ""
        return PreviewSnapshot(title: url.lastPathComponent,
            summary: "SpaceLens · \(delimiter == "\t" ? "TSV" : "CSV") · \(totalDataRows) 行 · \(rawHeader.count) 列\(limits)\(columnLimit)\(suffix)",
            body: source, truncated: truncated || omitted > 0 || rawHeader.count > maximumColumns,
            contentKind: .table,
            table: .init(columns: columns, rows: Array(visibleRows), omittedRowCount: omitted))
    }

    private static func parseDelimited(_ source: String, delimiter: Character) throws -> ParsedTable {
        if source.isEmpty { return ParsedTable(rows: [[]], totalRowCount: 1) }
        var rows: [[String]] = []
        var totalRowCount = 0
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = source.makeIterator()
        while let character = iterator.next() {
            try Task.checkCancellation()
            if quoted {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") }
                        else {
                            quoted = false
                            if next == delimiter { row.append(field); field = "" }
                            else if next == "\n" {
                                row.append(field); totalRowCount += 1
                                if rows.count < maximumRows + 1 { rows.append(row) }
                                row = []; field = ""
                            }
                            else if next != "\r" && !next.isWhitespace {
                                throw PreviewFailure.malformedText("表格格式错误：引号结束后存在意外字符。")
                            }
                        }
                    } else { quoted = false }
                } else { field.append(character) }
            } else if character == "\"" && field.isEmpty {
                quoted = true
            } else if character == delimiter {
                row.append(field); field = ""
            } else if character == "\n" {
                row.append(field); totalRowCount += 1
                if rows.count < maximumRows + 1 { rows.append(row) }
                row = []; field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }
        guard !quoted else { throw PreviewFailure.malformedText("表格格式错误：存在未闭合的引号。") }
        if !field.isEmpty || !row.isEmpty {
            row.append(field); totalRowCount += 1
            if rows.count < maximumRows + 1 { rows.append(row) }
        }
        return ParsedTable(rows: rows, totalRowCount: totalRowCount)
    }

    private static func loadStructured(_ url: URL, source: String, lineDelimited: Bool,
                                       truncated: Bool, suffix: String) throws -> PreviewSnapshot {
        var budget = maximumJSONNodes
        let roots: [PreviewSnapshot.StructuredItem]
        if lineDelimited {
            let lines = source.split(whereSeparator: \.isNewline)
            let visible = lines.prefix(maximumRows)
            roots = try visible.enumerated().map { index, line in
                let value = try parseJSON(Data(line.utf8))
                return try structuredItem(key: "第 \(index + 1) 行", value: value, depth: 0, budget: &budget)
            }
        } else {
            let value = try parseJSON(Data(source.utf8))
            roots = [try structuredItem(key: "根", value: value, depth: 0, budget: &budget)]
        }
        return PreviewSnapshot(title: url.lastPathComponent,
            summary: "SpaceLens · \(lineDelimited ? "JSON Lines" : "JSON") · 结构化预览\(suffix)",
            body: source, truncated: truncated || budget == 0, contentKind: .structured,
            structuredItems: roots, language: "JSON")
    }

    private static func parseJSON(_ data: Data) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw PreviewFailure.malformedText("JSON 格式错误：\(error.localizedDescription)") }
    }

    private static func structuredItem(key: String, value: Any, depth: Int,
                                       budget: inout Int) throws -> PreviewSnapshot.StructuredItem {
        try Task.checkCancellation()
        guard depth <= maximumJSONDepth else {
            return .init(key: key, type: "已截断", value: "超过 \(maximumJSONDepth) 层")
        }
        guard budget > 0 else { return .init(key: key, type: "已截断", value: "达到节点上限") }
        budget -= 1
        if let dictionary = value as? [String: Any] {
            var children: [PreviewSnapshot.StructuredItem] = []
            for childKey in dictionary.keys.sorted() {
                guard budget > 0 else { break }
                children.append(try structuredItem(key: childKey, value: dictionary[childKey]!, depth: depth + 1, budget: &budget))
            }
            return .init(key: key, type: "对象", children: children)
        }
        if let array = value as? [Any] {
            var children: [PreviewSnapshot.StructuredItem] = []
            for (index, childValue) in array.enumerated() {
                guard budget > 0 else { break }
                children.append(try structuredItem(key: "[\(index)]", value: childValue, depth: depth + 1, budget: &budget))
            }
            return .init(key: key, type: "数组", children: children)
        }
        if value is NSNull { return .init(key: key, type: "Null", value: "null") }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .init(key: key, type: "布尔值", value: number.boolValue ? "true" : "false")
            }
            return .init(key: key, type: "数字", value: number.stringValue)
        }
        return .init(key: key, type: "字符串", value: value as? String ?? String(describing: value))
    }

    private static func languageName(extension ext: String, filename: String) -> String {
        if specialNames.contains(filename) { return filename.hasPrefix(".") ? "配置" : filename.capitalized }
        let names = ["py": "Python", "js": "JavaScript", "ts": "TypeScript", "rb": "Ruby",
                     "rs": "Rust", "cpp": "C++", "cxx": "C++", "sh": "Shell", "bash": "Shell",
                     "zsh": "Shell", "yml": "YAML", "yaml": "YAML", "toml": "TOML",
                     "diff": "Diff", "patch": "Patch", "graphql": "GraphQL", "gql": "GraphQL"]
        return names[ext] ?? (ext.isEmpty ? "代码" : ext.uppercased())
    }

    private static func lineCount(_ value: String) -> Int {
        value.isEmpty ? 0 : value.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}
