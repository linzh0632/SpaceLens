import Foundation

/// Loads the content of one entry that lives *inside* a container (a folder or an archive), so
/// the preview extension can show it in the container's detail pane.
///
/// The two sources differ in what they can reach:
/// - A folder child is a real file on disk, so the whole `PreviewLoader` pipeline applies.
/// - An archive entry exists only in memory. It is extracted with a hard byte limit and is never
///   written to disk, so only parsers that accept `Data` are reachable. Types that need a file
///   path (SQLite, Parquet/Arrow/Feather/Avro) and nested containers are refused with an explicit
///   message rather than silently degrading.
public enum EmbeddedPreviewLoader {
    public enum Source: Sendable {
        case directoryChild(root: URL, relativePath: String)
        case archiveEntry(archive: URL, path: String)
    }

    /// Hard ceiling for a single entry read out of an archive.
    public static let maximumEntryBytes = 16 * 1024 * 1024
    /// Sequential formats (tar and friends) have to scan forward; give up instead of hanging.
    static let maximumScanSeconds: Double = 5

    public static func load(_ source: Source) throws -> PreviewSnapshot {
        switch source {
        case .directoryChild(let root, let relativePath):
            return try loadDirectoryChild(root: root, relativePath: relativePath)
        case .archiveEntry(let archive, let path):
            return try loadArchiveEntry(archive: archive, path: path)
        }
    }

    // MARK: - Folder children

    private static func loadDirectoryChild(root: URL, relativePath: String) throws -> PreviewSnapshot {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty, !components.contains("..") else {
            throw PreviewFailure.unsupportedData("条目路径不安全，已拒绝预览。")
        }
        // Built from the raw path rather than `appendingPathComponent` so file names containing
        // "%" or "#" are not percent-encoded twice.
        var child = root
        for component in components {
            child = URL(fileURLWithPath: child.path + "/" + String(component))
            let componentValues = try child.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard componentValues.isSymbolicLink != true else {
                throw PreviewFailure.unsupportedData("链接不会被读取，已拒绝预览。")
            }
        }
        // Resolve every component again before checking containment to defend against a path being
        // replaced after the listing was created.
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedChild = child.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedChild.path.hasPrefix(resolvedRoot.path + "/") else {
            throw PreviewFailure.unsupportedData("条目路径超出容器范围，已拒绝预览。")
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey,
                                        .isDirectoryKey, .isPackageKey]
        let values = try resolvedChild.resourceValues(forKeys: keys)
        guard values.isRegularFile == true else {
            throw PreviewFailure.unsupportedData(
                values.isDirectory == true ? "这是一个文件夹，请展开它而不是预览内容。" : "这不是一个普通文件。")
        }
        return try PreviewLoader.load(resolvedChild)
    }

    // MARK: - Archive entries

    private static func loadArchiveEntry(archive: URL, path: String) throws -> PreviewSnapshot {
        guard !path.isEmpty, !path.hasSuffix("/") else {
            throw PreviewFailure.unsupportedData("归档内目录没有可直接预览的内容。")
        }
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()

        // Refuse the types that would need a temporary file, before doing any extraction work.
        if !ext.isEmpty, ColumnarPreview.extensions.contains(ext) {
            throw PreviewFailure.unsupportedData(
                "归档内的 \(ext.uppercased()) 需要文件路径，SpaceLens 不会为了预览而写入磁盘。")
        }
        if ext == "db" || ext == "sqlite" || ext == "sqlite3" {
            throw PreviewFailure.unsupportedData(
                "归档内的 SQLite 数据库需要文件路径，SpaceLens 不会为了预览而写入磁盘。")
        }
        if ext == "zip" || ArchivePreview.extensions.contains(ext) {
            throw PreviewFailure.unsupportedData("归档内嵌套的压缩包暂不支持预览。")
        }

        let (data, truncated) = try ArchiveEntryReader.read(archive: archive, path: path,
                                                            limit: maximumEntryBytes)
        try Task.checkCancellation()
        if ImagePreview.extensions.contains(ext) {
            guard !truncated else {
                throw PreviewFailure.unsupportedData(
                    "归档内的图片超过 \(formatBytes(Int64(maximumEntryBytes))) 的安全读取上限。")
            }
            return try ImagePreview.load(data: data, name: name)
        }
        if ext == "plist" {
            return try PropertyListPreview.load(data: data, name: name)
        }
        guard CommonTextPreview.supports(name: name, ext: ext) else {
            throw PreviewFailure.unsupportedData(
                "归档内暂不支持预览这种文件\(ext.isEmpty ? "" : "（.\(ext)）")。")
        }
        return try CommonTextPreview.load(data: data, truncated: truncated,
                                          byteLimit: maximumEntryBytes, name: name, ext: ext)
    }
}

/// Extracts a single archive entry into memory. Nothing is written to disk.
private enum ArchiveEntryReader {
    private static let archiveOK: Int32 = 0
    private static let archiveEOF: Int32 = 1
    private static let archiveWarn: Int32 = -20

    static func read(archive url: URL, path: String, limit: Int) throws -> (Data, Bool) {
        guard let archive = reader_new() else {
            throw PreviewFailure.damagedArchive("无法初始化归档读取器")
        }
        defer { _ = reader_free(archive) }
        guard reader_support_filter_all(archive) >= archiveWarn,
              reader_support_format_all(archive) >= archiveWarn else {
            throw PreviewFailure.unsupportedArchive("系统归档库无法启用所需格式")
        }
        if url.pathExtension.lowercased() != "tar", reader_support_format_raw(archive) < archiveWarn {
            throw PreviewFailure.unsupportedArchive("系统归档库无法启用独立压缩流")
        }
        guard url.path.withCString({ reader_open(archive, $0, 64 * 1024) }) == archiveOK else {
            throw failure(archive)
        }

        let deadline = Date().addingTimeInterval(EmbeddedPreviewLoader.maximumScanSeconds)
        var scanned = 0
        while true {
            try Task.checkCancellation()
            if Date() > deadline {
                throw PreviewFailure.unsupportedArchive("在归档中查找条目超时（已扫描 \(scanned) 项）。")
            }
            var entry: OpaquePointer?
            let status = reader_next_header(archive, &entry)
            if status == archiveEOF {
                throw PreviewFailure.unsupportedArchive("归档中找不到条目「\(path)」。")
            }
            guard status >= archiveWarn, let entry else { throw failure(archive) }
            scanned += 1
            let reported = reader_entry_path_utf8(entry).map(String.init(cString:))
                ?? reader_entry_path(entry).map(String.init(cString:)) ?? ""
            // The container listing stores archive paths normalized (leading "./" removed), so
            // the archive-reported name has to be normalized the same way before comparing.
            guard ArchivePreview.normalized(reported) == path else {
                _ = reader_data_skip(archive)
                continue
            }
            if reader_entry_encrypted(entry) == 1 {
                throw PreviewFailure.unsupportedArchive("条目「\(path)」已加密，无法预览内容。")
            }
            return try drain(archive, limit: limit, deadline: deadline)
        }
    }

    private static func drain(_ archive: OpaquePointer?, limit: Int,
                              deadline: Date) throws -> (Data, Bool) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            if Date() > deadline { return (data, true) }
            let count = buffer.withUnsafeMutableBytes {
                reader_data(archive, $0.baseAddress, $0.count)
            }
            if count == 0 { return (data, false) }
            if count < 0 { throw failure(archive) }
            if data.count + count > limit {
                data.append(contentsOf: buffer[0..<(limit - data.count)])
                return (data, true)
            }
            data.append(contentsOf: buffer[0..<count])
        }
    }

    private static func failure(_ archive: OpaquePointer?) -> PreviewFailure {
        let detail = reader_error(archive).map(String.init(cString:)) ?? "无法读取归档"
        return .damagedArchive(detail)
    }
}

@_silgen_name("archive_read_new") private func reader_new() -> OpaquePointer?
@_silgen_name("archive_read_support_filter_all") private func reader_support_filter_all(_ archive: OpaquePointer?) -> Int32
@_silgen_name("archive_read_support_format_all") private func reader_support_format_all(_ archive: OpaquePointer?) -> Int32
@_silgen_name("archive_read_support_format_raw") private func reader_support_format_raw(_ archive: OpaquePointer?) -> Int32
@_silgen_name("archive_read_open_filename") private func reader_open(_ archive: OpaquePointer?, _ path: UnsafePointer<CChar>?, _ blockSize: Int) -> Int32
@_silgen_name("archive_read_next_header") private func reader_next_header(_ archive: OpaquePointer?, _ entry: UnsafeMutablePointer<OpaquePointer?>?) -> Int32
@_silgen_name("archive_read_data") private func reader_data(_ archive: OpaquePointer?, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int
@_silgen_name("archive_read_data_skip") private func reader_data_skip(_ archive: OpaquePointer?) -> Int32
@_silgen_name("archive_read_free") private func reader_free(_ archive: OpaquePointer?) -> Int32
@_silgen_name("archive_error_string") private func reader_error(_ archive: OpaquePointer?) -> UnsafePointer<CChar>?
@_silgen_name("archive_entry_pathname") private func reader_entry_path(_ entry: OpaquePointer?) -> UnsafePointer<CChar>?
@_silgen_name("archive_entry_pathname_utf8") private func reader_entry_path_utf8(_ entry: OpaquePointer?) -> UnsafePointer<CChar>?
@_silgen_name("archive_entry_is_encrypted") private func reader_entry_encrypted(_ entry: OpaquePointer?) -> Int32
