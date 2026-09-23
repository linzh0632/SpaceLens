import Foundation

public struct PreviewSnapshot: Sendable {
    public let title: String
    public let summary: String
    public let body: String
    public let truncated: Bool
}

public enum PreviewFailure: LocalizedError {
    case unsupported, invalidText
    public var errorDescription: String? {
        switch self {
        case .unsupported: return "此原型仅支持文件夹和 .spacelens 验收文件。"
        case .invalidText: return "验收文件必须是 UTF-8 文本。"
        }
    }
}

public enum PreviewLoader {
    public static let maximumEntries = 100
    public static let maximumBytes = 64 * 1024

    /// Shallow, bounded inspection. Never follows directory symlinks or opens child content.
    public static func load(_ url: URL) throws -> PreviewSnapshot {
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        let values = try url.resourceValues(forKeys: keys)
        if values.isDirectory == true && values.isSymbolicLink != true {
            var enumerationError: Error?
            guard let iterator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: Array(keys),
                options: [.skipsSubdirectoryDescendants],
                errorHandler: { _, error in enumerationError = error; return false }
            ) else { throw CocoaError(.fileReadNoPermission) }
            var rows: [String] = []
            var truncated = false
            while let child = iterator.nextObject() as? URL {
                try Task.checkCancellation()
                if rows.count == maximumEntries { truncated = true; break }
                let metadata = try? child.resourceValues(forKeys: keys)
                let kind = metadata?.isSymbolicLink == true ? "链接" : metadata?.isDirectory == true ? "文件夹" : "文件"
                // Escape line controls so a filename cannot masquerade as additional entries.
                let name = child.lastPathComponent.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t")
                rows.append("[\(kind)] \(name)")
            }
            if let error = enumerationError { throw error }
            rows.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            return PreviewSnapshot(title: url.lastPathComponent,
                summary: "SpaceLens · 文件夹原型 · 当前层 \(rows.count) 项\(truncated ? "（已截断）" : "")",
                body: rows.isEmpty ? "这是一个空文件夹。" : rows.joined(separator: "\n"), truncated: truncated)
        }
        guard url.pathExtension.lowercased() == "spacelens", values.isSymbolicLink != true, values.isRegularFile == true else { throw PreviewFailure.unsupported }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        try Task.checkCancellation()
        let truncated = data.count > maximumBytes
        let prefix = Data(data.prefix(maximumBytes))
        // A bounded read may split the final UTF-8 scalar; remove at most its trailing bytes.
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
            body: text, truncated: truncated)
    }
}
