import Foundation

enum DocumentPreview {
    static let extensions: Set<String> = [
        "mdx", "qmd", "rmd", "rst", "rest", "adoc", "asciidoc", "tex", "ipynb"
    ]
    private static let maximumNotebookCells = 200
    private static let maximumOutputsPerCell = 20
    private static let maximumOutputCharacters = 10_000

    static func load(source: String, truncated: Bool, name: String, ext: String,
                     byteLimit: Int) throws -> PreviewSnapshot {
        try Task.checkCancellation()
        let suffix = truncated ? " · 仅显示前 \(formatBytes(Int64(byteLimit)))" : ""
        if ext == "ipynb" {
            guard !truncated else {
                throw PreviewFailure.malformedText("Jupyter Notebook 超过 \(formatBytes(Int64(byteLimit))) 的安全读取上限。")
            }
            return try loadNotebook(name: name, source: source)
        }

        let format: String
        let body: String
        switch ext {
        case "mdx": format = "MDX"; body = source
        case "qmd": format = "Quarto Markdown"; body = source
        case "rmd": format = "R Markdown"; body = source
        case "rst", "rest": format = "reStructuredText"; body = normalizeRST(source)
        case "adoc", "asciidoc": format = "AsciiDoc"; body = normalizeAsciiDoc(source)
        case "tex": format = "TeX"; body = normalizeTeX(source)
        default: throw PreviewFailure.unsupported
        }
        return PreviewSnapshot(
            title: name,
            summary: "SpaceLens · \(format) · \(lineCount(source)) 行\(suffix)",
            body: body,
            truncated: truncated,
            contentKind: .markdown,
            language: format
        )
    }

    private static func loadNotebook(name: String, source: String) throws -> PreviewSnapshot {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(source.utf8))
        } catch {
            throw PreviewFailure.malformedText("Jupyter Notebook 格式错误：\(error.localizedDescription)")
        }
        guard let root = object as? [String: Any],
              let cells = root["cells"] as? [[String: Any]],
              root["nbformat"] is NSNumber else {
            throw PreviewFailure.malformedText("Jupyter Notebook 格式错误：缺少 nbformat 或 cells。")
        }
        let language = notebookLanguage(root)
        let visible = cells.prefix(maximumNotebookCells)
        var rendered: [String] = []
        var markdownCount = 0
        var codeCount = 0
        for (index, cell) in visible.enumerated() {
            try Task.checkCancellation()
            let type = cell["cell_type"] as? String ?? "raw"
            let text = joinedText(cell["source"])
            switch type {
            case "markdown":
                markdownCount += 1
                rendered.append(text)
            case "code":
                codeCount += 1
                rendered.append("```\(language)\n\(text)\n```")
                let outputs = (cell["outputs"] as? [[String: Any]] ?? []).prefix(maximumOutputsPerCell)
                for output in outputs {
                    if let value = notebookOutput(output), !value.isEmpty {
                        rendered.append("输出：\n```text\n\(clipped(value, limit: maximumOutputCharacters))\n```")
                    }
                }
            default:
                rendered.append("原始单元格 \(index + 1)：\n```text\n\(text)\n```")
            }
        }
        let limited = cells.count > maximumNotebookCells
        let limitNote = limited ? " · 仅显示前 \(maximumNotebookCells) 个单元格" : ""
        return PreviewSnapshot(
            title: name,
            summary: "SpaceLens · Jupyter Notebook · \(cells.count) 个单元格 · \(markdownCount) 个 Markdown · \(codeCount) 个代码\(limitNote)",
            body: rendered.joined(separator: "\n\n"),
            truncated: limited,
            contentKind: .markdown,
            language: "Jupyter Notebook"
        )
    }

    private static func notebookLanguage(_ root: [String: Any]) -> String {
        let metadata = root["metadata"] as? [String: Any]
        let kernel = metadata?["kernelspec"] as? [String: Any]
        let info = metadata?["language_info"] as? [String: Any]
        return (info?["name"] as? String) ?? (kernel?["language"] as? String) ?? "text"
    }

    private static func notebookOutput(_ output: [String: Any]) -> String? {
        if let text = output["text"] { return joinedText(text) }
        if let data = output["data"] as? [String: Any], let plain = data["text/plain"] {
            return joinedText(plain)
        }
        if let name = output["ename"] as? String, let value = output["evalue"] as? String {
            return "\(name): \(value)"
        }
        return nil
    }

    private static func joinedText(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let values = value as? [String] { return values.joined() }
        return ""
    }

    private static func normalizeRST(_ source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0
        var codeBlock = false
        while index < lines.count {
            let line = lines[index]
            if index + 1 < lines.count, !line.trimmingCharacters(in: .whitespaces).isEmpty,
               let level = rstHeadingLevel(lines[index + 1], titleLength: line.count) {
                output.append(String(repeating: "#", count: level) + " " + line.trimmingCharacters(in: .whitespaces))
                index += 2
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(".. code-block::") {
                let language = trimmed.split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                output.append("```\(language)")
                codeBlock = true
            } else if codeBlock && !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                output.append("```")
                output.append(line)
                codeBlock = false
            } else if codeBlock {
                output.append(line.hasPrefix("   ") ? String(line.dropFirst(3)) : line)
            } else {
                output.append(line)
            }
            index += 1
        }
        if codeBlock { output.append("```") }
        return output.joined(separator: "\n")
    }

    private static func rstHeadingLevel(_ value: String, titleLength: Int) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= min(3, titleLength), let marker = trimmed.first,
              Set("=-~^\"`'").contains(marker), trimmed.allSatisfy({ $0 == marker }) else { return nil }
        switch marker { case "=": return 1; case "-": return 2; default: return 3 }
    }

    private static func normalizeAsciiDoc(_ source: String) -> String {
        var output: [String] = []
        var pendingLanguage = ""
        var inCode = false
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[source") && trimmed.hasSuffix("]") {
                let content = trimmed.dropFirst().dropLast()
                pendingLanguage = content.split(separator: ",").dropFirst().first.map(String.init) ?? ""
                continue
            }
            if trimmed == "----" {
                output.append(inCode ? "```" : "```\(pendingLanguage)")
                inCode.toggle()
                pendingLanguage = ""
                continue
            }
            if !inCode {
                let marks = line.prefix(while: { $0 == "=" }).count
                if marks > 0, marks <= 6, line.dropFirst(marks).first == " " {
                    output.append(String(repeating: "#", count: marks) + line.dropFirst(marks))
                    continue
                }
            }
            output.append(line)
        }
        if inCode { output.append("```") }
        return output.joined(separator: "\n")
    }

    private static func normalizeTeX(_ source: String) -> String {
        var output: [String] = []
        var verbatim = false
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "\\begin{verbatim}" || trimmed.hasPrefix("\\begin{lstlisting}") {
                output.append("```text"); verbatim = true; continue
            }
            if trimmed == "\\end{verbatim}" || trimmed == "\\end{lstlisting}" {
                output.append("```"); verbatim = false; continue
            }
            if !verbatim, let heading = texHeading(trimmed) { output.append(heading); continue }
            if !verbatim, trimmed.hasPrefix("\\item ") {
                output.append("- " + trimmed.dropFirst(6)); continue
            }
            output.append(line)
        }
        if verbatim { output.append("```") }
        return output.joined(separator: "\n")
    }

    private static func texHeading(_ line: String) -> String? {
        let commands = [("\\chapter{", 1), ("\\section{", 1), ("\\subsection{", 2), ("\\subsubsection{", 3)]
        for (prefix, level) in commands where line.hasPrefix(prefix) && line.hasSuffix("}") {
            return String(repeating: "#", count: level) + " " + line.dropFirst(prefix.count).dropLast()
        }
        return nil
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        value.count <= limit ? value : String(value.prefix(limit)) + "…"
    }

    private static func lineCount(_ value: String) -> Int {
        value.isEmpty ? 0 : value.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}
