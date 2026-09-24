import Foundation

enum ArchivePreview {
    private static let archiveOK: Int32 = 0
    private static let archiveEOF: Int32 = 1
    private static let archiveWarn: Int32 = -20
    private static let modeMask: UInt32 = 0o170000
    private static let directoryMode: UInt32 = 0o040000
    private static let symbolicLinkMode: UInt32 = 0o120000

    static let extensions: Set<String> = ["tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz"]

    static func load(_ url: URL, entryLimit: Int) throws -> PreviewSnapshot {
        guard let archive = archive_read_new() else {
            throw PreviewFailure.damagedArchive("无法初始化归档读取器")
        }
        defer { _ = archive_read_free(archive) }

        guard archive_read_support_filter_all(archive) >= archiveWarn,
              archive_read_support_format_all(archive) >= archiveWarn else {
            throw PreviewFailure.unsupportedArchive("系统归档库无法启用所需格式")
        }
        let requiresCompression = url.pathExtension.lowercased() != "tar"
        if requiresCompression, archive_read_support_format_raw(archive) < archiveWarn {
            throw PreviewFailure.unsupportedArchive("系统归档库无法启用独立压缩流")
        }
        let opened = url.path.withCString {
            archive_read_open_filename(archive, $0, 64 * 1024)
        }
        guard opened == archiveOK else { throw archiveError(archive) }

        var items: [PreviewSnapshot.Item] = []
        var rows: [String] = []
        var fileCount = 0
        var folderCount = 0
        var linkCount = 0
        var unsafeCount = 0
        var encryptedCount = 0
        var totalBytes: Int64 = 0
        var truncated = false
        var entry: OpaquePointer?

        while true {
            try Task.checkCancellation()
            entry = nil
            let status = archive_read_next_header(archive, &entry)
            if status == archiveEOF { break }
            guard status >= archiveWarn, let entry else { throw archiveError(archive) }
            if items.isEmpty, requiresCompression,
               (archive_filter_name(archive, 0).map(String.init(cString:)) ?? "none").lowercased() == "none" {
                throw PreviewFailure.damagedArchive("文件没有有效的压缩数据层")
            }

            guard items.count < entryLimit else {
                truncated = true
                break
            }
            let rawPath = archive_entry_pathname_utf8(entry).map(String.init(cString:))
                ?? archive_entry_pathname(entry).map(String.init(cString:))
                ?? "<无法解码的文件名>"
            let path = normalized(rawPath)
            if path.isEmpty {
                _ = archive_read_data_skip(archive)
                continue
            }

            let mode = archive_entry_filetype(entry) & modeMask
            let kind: PreviewSnapshot.Item.Kind
            let size: Int64?
            switch mode {
            case directoryMode:
                kind = .folder
                size = nil
                folderCount += 1
            case symbolicLinkMode:
                kind = .link
                size = nil
                linkCount += 1
            default:
                kind = .file
                size = archive_entry_size_is_set(entry) != 0 ? max(0, archive_entry_size(entry)) : nil
                fileCount += 1
                if let size {
                    let sum = totalBytes.addingReportingOverflow(size)
                    totalBytes = sum.overflow ? Int64.max : sum.partialValue
                }
            }

            var warnings: [String] = []
            if isUnsafePath(path) {
                warnings.append("不安全路径")
                unsafeCount += 1
            }
            if archive_entry_is_encrypted(entry) == 1 {
                warnings.append("已加密")
                encryptedCount += 1
            }
            let modificationDate: Date? = archive_entry_mtime_is_set(entry) != 0
                ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry))) : nil
            let filter = filterName(archive)
            let displayKind: String
            switch kind {
            case .folder: displayKind = "文件夹"
            case .link: displayKind = "链接"
            default: displayKind = "文件"
            }
            let sizeText = size.map { " · \(formatBytes($0))" } ?? ""
            let dateText = modificationDate.map { " · \(formatDate($0))" } ?? ""
            let warningText = warnings.isEmpty ? "" : " · ⚠︎ " + warnings.joined(separator: "、")
            rows.append("[\(displayKind)] \(escaped(path))\(sizeText) · \(filter)\(dateText)\(warningText)")
            items.append(.init(path: escaped(path), sourcePath: path, kind: kind, size: size,
                               modificationDate: modificationDate,
                               compression: filter, warnings: warnings))
            let skipped = archive_read_data_skip(archive)
            guard skipped >= archiveWarn else { throw archiveError(archive) }
        }

        var notices: [String] = []
        if truncated { notices.append("仅显示前 \(entryLimit) 项") }
        if linkCount > 0 { notices.append("\(linkCount) 项链接") }
        if encryptedCount > 0 { notices.append("\(encryptedCount) 项加密") }
        if unsafeCount > 0 { notices.append("\(unsafeCount) 项路径不安全") }
        let noticeText = notices.isEmpty ? "" : " · ⚠︎ " + notices.joined(separator: "、")
        let type = archiveType(url)
        let format = formatName(archive)
        return PreviewSnapshot(
            title: url.lastPathComponent,
            summary: "SpaceLens · \(type) · \(folderCount) 个文件夹 · \(fileCount) 个文件 · \(formatBytes(totalBytes)) · \(format)\(noticeText)",
            body: rows.isEmpty ? "这个归档中没有可显示的条目。" : rows.joined(separator: "\n"),
            truncated: truncated,
            contentKind: .archive,
            items: items
        )
    }

    private static func archiveError(_ archive: OpaquePointer?) -> PreviewFailure {
        let detail = archive_error_string(archive).map(String.init(cString:)) ?? "无法读取归档"
        return .damagedArchive(detail)
    }

    private static func formatName(_ archive: OpaquePointer?) -> String {
        archive_format_name(archive).map(String.init(cString:)) ?? "归档"
    }

    private static func filterName(_ archive: OpaquePointer?) -> String {
        let value = archive_filter_name(archive, 0).map(String.init(cString:)) ?? "none"
        switch value.lowercased() {
        case "none": return "未压缩"
        case "gzip": return "GZIP"
        case "bzip2": return "BZIP2"
        case "xz": return "XZ"
        default: return value.uppercased()
        }
    }

    private static func archiveType(_ url: URL) -> String {
        let lower = url.lastPathComponent.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") { return "TGZ" }
        if lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tbz") || lower.hasSuffix(".tbz2") { return "TBZ2" }
        if lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") { return "TXZ" }
        return url.pathExtension.uppercased()
    }

    /// Shared with `EmbeddedPreviewLoader`, which must match stored entry paths against the
    /// names libarchive reports for the same archive.
    static func normalized(_ value: String) -> String {
        var result = value
        while result.hasPrefix("./") { result.removeFirst(2) }
        if result == "." { return "" }
        return result
    }

    private static func isUnsafePath(_ value: String) -> Bool {
        value.hasPrefix("/") || value.hasPrefix("\\") || value.contains("\0") ||
            value.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..") ||
            (value.count >= 2 && value[value.index(after: value.startIndex)] == ":")
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

@_silgen_name("archive_read_new") private func archive_read_new() -> OpaquePointer?
@_silgen_name("archive_read_support_filter_all") private func archive_read_support_filter_all(_ archive: OpaquePointer?) -> Int32
@_silgen_name("archive_read_support_format_all") private func archive_read_support_format_all(_ archive: OpaquePointer?) -> Int32
@_silgen_name("archive_read_support_format_raw") private func archive_read_support_format_raw(_ archive: OpaquePointer?) -> Int32
@_silgen_name("archive_read_open_filename") private func archive_read_open_filename(_ archive: OpaquePointer?, _ path: UnsafePointer<CChar>?, _ blockSize: Int) -> Int32
@_silgen_name("archive_read_next_header") private func archive_read_next_header(_ archive: OpaquePointer?, _ entry: UnsafeMutablePointer<OpaquePointer?>?) -> Int32
@_silgen_name("archive_read_data_skip") private func archive_read_data_skip(_ archive: OpaquePointer?) -> Int32
@_silgen_name("archive_read_free") private func archive_read_free(_ archive: OpaquePointer?) -> Int32
@_silgen_name("archive_error_string") private func archive_error_string(_ archive: OpaquePointer?) -> UnsafePointer<CChar>?
@_silgen_name("archive_format_name") private func archive_format_name(_ archive: OpaquePointer?) -> UnsafePointer<CChar>?
@_silgen_name("archive_filter_name") private func archive_filter_name(_ archive: OpaquePointer?, _ index: Int32) -> UnsafePointer<CChar>?
@_silgen_name("archive_entry_pathname") private func archive_entry_pathname(_ entry: OpaquePointer?) -> UnsafePointer<CChar>?
@_silgen_name("archive_entry_pathname_utf8") private func archive_entry_pathname_utf8(_ entry: OpaquePointer?) -> UnsafePointer<CChar>?
@_silgen_name("archive_entry_size") private func archive_entry_size(_ entry: OpaquePointer?) -> Int64
@_silgen_name("archive_entry_size_is_set") private func archive_entry_size_is_set(_ entry: OpaquePointer?) -> Int32
@_silgen_name("archive_entry_filetype") private func archive_entry_filetype(_ entry: OpaquePointer?) -> UInt32
@_silgen_name("archive_entry_mtime") private func archive_entry_mtime(_ entry: OpaquePointer?) -> Int64
@_silgen_name("archive_entry_mtime_is_set") private func archive_entry_mtime_is_set(_ entry: OpaquePointer?) -> Int32
@_silgen_name("archive_entry_is_encrypted") private func archive_entry_is_encrypted(_ entry: OpaquePointer?) -> Int32
