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
        "sql", "graphql", "gql", "yaml", "yml", "toml", "ini", "conf", "config", "env", "diff", "patch",
        "asm", "awk", "bat", "bazel", "bzl", "cmake", "cmd", "coffee", "cr", "d", "f", "f03", "f08",
        "f90", "f95", "for", "gd", "gradle", "groovy", "hcl", "hs", "jl", "lhs", "litcoffee", "log",
        "ml", "mli", "nim", "nu", "proto", "raku", "rakumod", "rakutest", "rkt", "s", "scm", "sol",
        "ss", "star", "sv", "svh", "tcl", "tf", "tfvars", "v", "vh", "xsd", "xsl", "xslt", "zig"
    ]
    private static let plainExtensions: Set<String> = ["txt", "text", "log"]
    private static let specialNames: Set<String> = [
        "dockerfile", "makefile", "gemfile", "podfile", "rakefile", "license", "readme", "cmakelists.txt",
        "build", "workspace", ".gitignore", ".gitattributes", ".editorconfig"
    ]
    private static let maximumRows = 1_000
    private static let maximumColumns = 100
    private static let maximumJSONNodes = 10_000
    private static let maximumJSONDepth = 50

    static func load(_ url: URL, byteLimit: Int) throws -> PreviewSnapshot {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        guard supports(name: name, ext: ext) else { throw PreviewFailure.unsupported }
        let (data, truncated) = try readBounded(url, byteLimit: byteLimit)
        return try load(data: data, truncated: truncated, byteLimit: byteLimit, name: name, ext: ext)
    }

    /// Whether `name`/`ext` is handled by the text pipeline. The container detail pane needs to
    /// decide this from an archive entry's name alone, without touching the file system.
    static func supports(name: String, ext: String) -> Bool {
        let filename = name.lowercased()
        return markdownExtensions.contains(ext) || tableExtensions.contains(ext) ||
            structuredExtensions.contains(ext) || codeExtensions.contains(ext) ||
            plainExtensions.contains(ext) || DocumentPreview.extensions.contains(ext) ||
            DiagramPreview.extensions.contains(ext) || specialNames.contains(filename)
    }

    /// Entry point for content already in memory, e.g. a file read out of an archive.
    static func load(data: Data, truncated: Bool, byteLimit: Int,
                     name: String, ext: String) throws -> PreviewSnapshot {
        let filename = name.lowercased()
        guard supports(name: name, ext: ext) else { throw PreviewFailure.unsupported }
        let (source, textTruncated) = try decodeText(data, truncated: truncated)
        if DocumentPreview.extensions.contains(ext) {
            return try DocumentPreview.load(source: source, truncated: textTruncated,
                                            name: name, ext: ext, byteLimit: byteLimit)
        }
        if DiagramPreview.extensions.contains(ext) {
            return try DiagramPreview.load(source: source, truncated: textTruncated,
                                           name: name, ext: ext, byteLimit: byteLimit)
        }
        try Task.checkCancellation()
        let suffix = textTruncated ? L10n.text(" · 仅显示前 \(formatBytes(Int64(byteLimit)))", " · showing the first \(formatBytes(Int64(byteLimit))) only") : ""
        if markdownExtensions.contains(ext) {
            return PreviewSnapshot(title: name,
                summary: L10n.text("SpaceLens · Markdown · \(L10n.count(lineCount(source), "行", "line", "lines"))\(suffix)", "SpaceLens · Markdown · \(L10n.count(lineCount(source), "行", "line", "lines"))\(suffix)"), body: source,
                truncated: textTruncated, contentKind: .markdown, language: "Markdown")
        }
        if tableExtensions.contains(ext) {
            return try loadTable(name: name, source: source, delimiter: ext == "tsv" ? "\t" : ",", truncated: textTruncated, suffix: suffix)
        }
        if structuredExtensions.contains(ext) {
            return try loadStructured(name: name, source: source, lineDelimited: ext != "json", truncated: textTruncated, suffix: suffix)
        }
        let language = languageName(extension: ext, filename: filename)
        let kind: PreviewSnapshot.ContentKind = codeExtensions.contains(ext) || specialNames.contains(filename) ? .code : .text
        return PreviewSnapshot(title: name,
            summary: L10n.text("SpaceLens · \(kind == .code ? language : "文本") · \(L10n.count(lineCount(source), "行", "line", "lines"))\(suffix)",
                              "SpaceLens · \(kind == .code ? language : "Text") · \(L10n.count(lineCount(source), "行", "line", "lines"))\(suffix)"),
            body: source, truncated: textTruncated, contentKind: kind, language: language)
    }

    /// Reads at most `byteLimit` bytes, plus one extra byte only to detect truncation.
    static func readBounded(_ url: URL, byteLimit: Int) throws -> (Data, Bool) {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: byteLimit + 1) ?? Data()
        return (Data(data.prefix(byteLimit)), data.count > byteLimit)
    }

    /// Decodes UTF-8 or BOM-marked UTF-16 text. When `truncated`, a multi-byte character cut in
    /// half at the limit is dropped rather than failing the whole preview.
    static func decodeText(_ data: Data, truncated: Bool) throws -> (String, Bool) {
        var prefix = data
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

    private static func loadTable(name: String, source: String, delimiter: Character,
                                  truncated: Bool, suffix: String) throws -> PreviewSnapshot {
        let parsed = try parseDelimited(source, delimiter: delimiter)
        let rawHeader = parsed.rows.first ?? []
        let width = min(max(1, rawHeader.count), maximumColumns)
        let columns = columnNames(rawHeader, width: width)
        let allRows = parsed.rows.dropFirst()
        let visibleRows = allRows.prefix(maximumRows).map { row in
            (0..<width).map { $0 < row.count ? row[$0] : "" }
        }
        let totalDataRows = max(0, parsed.totalRowCount - 1)
        let omitted = max(0, totalDataRows - visibleRows.count)
        let limits = omitted > 0 ? L10n.text(" · 另有 \(L10n.count(omitted, "行未显示", "more row not shown", "more rows not shown"))", " · \(L10n.count(omitted, "行未显示", "more row not shown", "more rows not shown"))") : ""
        let columnLimit = rawHeader.count > maximumColumns ? L10n.text(" · 仅显示前 \(L10n.count(maximumColumns, "列", "column", "columns"))", " · showing the first \(L10n.count(maximumColumns, "列", "column", "columns")) only") : ""
        return PreviewSnapshot(title: name,
            summary: L10n.text("SpaceLens · \(delimiter == "\t" ? "TSV" : "CSV") · \(L10n.count(totalDataRows, "行", "row", "rows")) · \(L10n.count(rawHeader.count, "列", "column", "columns"))\(limits)\(columnLimit)\(suffix)",
                              "SpaceLens · \(delimiter == "\t" ? "TSV" : "CSV") · \(L10n.count(totalDataRows, "行", "row", "rows")) · \(L10n.count(rawHeader.count, "列", "column", "columns"))\(limits)\(columnLimit)\(suffix)"),
            body: source, truncated: truncated || omitted > 0 || rawHeader.count > maximumColumns,
            contentKind: .table,
            table: .init(columns: columns, rows: Array(visibleRows), omittedRowCount: omitted))
    }

    /// Column titles for a table: empty header cells fall back to "Column N" and duplicate names get
    /// a numeric suffix.
    static func columnNames(_ header: [String], width: Int) -> [String] {
        var used: [String: Int] = [:]
        return (0..<width).map { index -> String in
            let base = index < header.count && !header[index].isEmpty ? header[index] : L10n.text("列 \(index + 1)", "Column \(index + 1)")
            let occurrence = (used[base] ?? 0) + 1
            used[base] = occurrence
            return occurrence == 1 ? base : "\(base) (\(occurrence))"
        }
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
                                throw PreviewFailure.malformedText(L10n.text("表格格式错误：引号结束后存在意外字符。", "Invalid table: unexpected characters after a closing quote."))
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
        guard !quoted else { throw PreviewFailure.malformedText(L10n.text("表格格式错误：存在未闭合的引号。", "Invalid table: an unterminated quote.")) }
        if !field.isEmpty || !row.isEmpty {
            row.append(field); totalRowCount += 1
            if rows.count < maximumRows + 1 { rows.append(row) }
        }
        return ParsedTable(rows: rows, totalRowCount: totalRowCount)
    }

    private static func loadStructured(name: String, source: String, lineDelimited: Bool,
                                       truncated: Bool, suffix: String) throws -> PreviewSnapshot {
        var budget = maximumJSONNodes
        let roots: [PreviewSnapshot.StructuredItem]
        if lineDelimited {
            let lines = source.split(whereSeparator: \.isNewline)
            let visible = lines.prefix(maximumRows)
            roots = try visible.enumerated().map { index, line in
                let value = try parseJSON(Data(line.utf8))
                return try structuredItem(key: L10n.text("第 \(index + 1) 行", "Row \(index + 1)"), value: value, depth: 0, budget: &budget)
            }
        } else {
            let value = try parseJSON(Data(source.utf8))
            roots = [try structuredItem(key: L10n.text("根", "Root"), value: value, depth: 0, budget: &budget)]
        }
        return PreviewSnapshot(title: name,
            summary: L10n.text("SpaceLens · \(lineDelimited ? "JSON Lines" : "JSON") · 结构化预览\(suffix)",
                              "SpaceLens · \(lineDelimited ? "JSON Lines" : "JSON") · structured preview\(suffix)"),
            body: source, truncated: truncated || budget == 0, contentKind: .structured,
            structuredItems: roots, language: "JSON")
    }

    private static func parseJSON(_ data: Data) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw PreviewFailure.malformedText(L10n.text("JSON 格式错误：\(error.localizedDescription)", "Invalid JSON: \(error.localizedDescription)")) }
    }

    private static func structuredItem(key: String, value: Any, depth: Int,
                                       budget: inout Int) throws -> PreviewSnapshot.StructuredItem {
        try Task.checkCancellation()
        guard depth <= maximumJSONDepth else {
            return .init(key: key, type: L10n.text("已截断", "Truncated"), value: L10n.text("超过 \(L10n.count(maximumJSONDepth, "层", "level", "levels"))", "Deeper than \(L10n.count(maximumJSONDepth, "层", "level", "levels"))"))
        }
        guard budget > 0 else { return .init(key: key, type: L10n.text("已截断", "Truncated"), value: L10n.text("达到节点上限", "Node limit reached")) }
        budget -= 1
        if let dictionary = value as? [String: Any] {
            var children: [PreviewSnapshot.StructuredItem] = []
            for childKey in dictionary.keys.sorted() {
                guard budget > 0 else { break }
                children.append(try structuredItem(key: childKey, value: dictionary[childKey]!, depth: depth + 1, budget: &budget))
            }
            return .init(key: key, type: L10n.text("对象", "Object"), children: children)
        }
        if let array = value as? [Any] {
            var children: [PreviewSnapshot.StructuredItem] = []
            for (index, childValue) in array.enumerated() {
                guard budget > 0 else { break }
                children.append(try structuredItem(key: "[\(index)]", value: childValue, depth: depth + 1, budget: &budget))
            }
            return .init(key: key, type: L10n.text("数组", "Array"), children: children)
        }
        if value is NSNull { return .init(key: key, type: "Null", value: "null") }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .init(key: key, type: L10n.text("布尔值", "Boolean"), value: number.boolValue ? "true" : "false")
            }
            return .init(key: key, type: L10n.text("数字", "Number"), value: number.stringValue)
        }
        return .init(key: key, type: L10n.text("字符串", "String"), value: value as? String ?? String(describing: value))
    }

    private static func languageName(extension ext: String, filename: String) -> String {
        let specialLanguages = [
            "dockerfile": "Dockerfile", "makefile": "Makefile", "gemfile": "Ruby", "podfile": "Ruby",
            "rakefile": "Ruby", "license": "License", "readme": "README", "cmakelists.txt": "CMake",
            "build": "Bazel", "workspace": "Bazel", ".gitignore": "Git", ".gitattributes": "Git",
            ".editorconfig": "EditorConfig"
        ]
        if let special = specialLanguages[filename] { return special }
        let names = [
            "py": "Python", "js": "JavaScript", "ts": "TypeScript", "rb": "Ruby", "rs": "Rust",
            "cpp": "C++", "cxx": "C++", "sh": "Shell", "bash": "Shell", "zsh": "Shell",
            "yml": "YAML", "yaml": "YAML", "toml": "TOML", "diff": "Diff", "patch": "Patch",
            "graphql": "GraphQL", "gql": "GraphQL", "asm": "Assembly", "s": "Assembly",
            "awk": "AWK", "bat": "Batch", "cmd": "Batch", "bazel": "Bazel", "bzl": "Bazel",
            "star": "Starlark", "cmake": "CMake", "coffee": "CoffeeScript", "litcoffee": "Literate CoffeeScript",
            "cr": "Crystal", "d": "D", "f": "Fortran", "f03": "Fortran", "f08": "Fortran",
            "f90": "Fortran", "f95": "Fortran", "for": "Fortran", "gd": "GDScript",
            "gradle": "Gradle", "groovy": "Groovy", "hcl": "HCL", "hs": "Haskell", "lhs": "Haskell",
            "jl": "Julia", "ml": "OCaml", "mli": "OCaml", "nim": "Nim", "nu": "Nushell",
            "proto": "Protocol Buffers", "raku": "Raku", "rakumod": "Raku", "rakutest": "Raku",
            "rkt": "Racket", "scm": "Scheme", "ss": "Scheme", "sol": "Solidity", "sv": "SystemVerilog",
            "svh": "SystemVerilog", "v": "Verilog", "vh": "Verilog", "tcl": "Tcl",
            "tf": "Terraform", "tfvars": "Terraform", "xsd": "XML Schema", "xsl": "XSLT",
            "xslt": "XSLT", "zig": "Zig"
        ]
        return names[ext] ?? (ext.isEmpty ? L10n.text("代码", "Code") : ext.uppercased())
    }

    private static func lineCount(_ value: String) -> Int {
        value.isEmpty ? 0 : value.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}
