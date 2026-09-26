import Foundation

enum ZipPreview {
    private static let eocdSignature: UInt32 = 0x0605_4b50
    private static let centralSignature: UInt32 = 0x0201_4b50
    private static let maximumTailBytes = 65_557

    static func load(_ url: URL, entryLimit: Int) throws -> PreviewSnapshot {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else { throw PreviewFailure.damagedArchive(L10n.text("找不到结束记录", "Central directory record not found")) }
        let tailLength = Int(min(UInt64(maximumTailBytes), fileSize))
        try handle.seek(toOffset: fileSize - UInt64(tailLength))
        let tail = try readExactly(handle, count: tailLength)
        guard let eocdOffset = findEOCD(in: tail) else {
            throw PreviewFailure.damagedArchive(L10n.text("找不到结束记录", "Central directory record not found"))
        }
        let disk = tail.u16(eocdOffset + 4)
        let centralDisk = tail.u16(eocdOffset + 6)
        let entriesOnDisk = tail.u16(eocdOffset + 8)
        let totalEntries = tail.u16(eocdOffset + 10)
        let centralSize = tail.u32(eocdOffset + 12)
        let centralOffset = tail.u32(eocdOffset + 16)
        guard disk == 0, centralDisk == 0, entriesOnDisk == totalEntries else { throw PreviewFailure.unsupportedArchive(L10n.text("不支持分卷 ZIP", "Multi-part ZIP is not supported")) }
        guard totalEntries != UInt16.max, centralSize != UInt32.max, centralOffset != UInt32.max else { throw PreviewFailure.unsupportedArchive(L10n.text("M2 暂不支持 ZIP64", "ZIP64 is not supported yet")) }
        guard UInt64(centralOffset) + UInt64(centralSize) <= fileSize else { throw PreviewFailure.damagedArchive(L10n.text("中央目录超出文件范围", "Central directory is outside the file")) }

        try handle.seek(toOffset: UInt64(centralOffset))
        let count = Int(totalEntries)
        let visibleCount = min(count, entryLimit)
        var rows: [String] = []
        var items: [PreviewSnapshot.Item] = []
        var encryptedCount = 0
        var unsafeCount = 0
        var suspiciousCount = 0
        var fileCount = 0
        var folderCount = 0
        var totalUncompressed: UInt64 = 0
        var centralBytesRead: UInt64 = 0
        for _ in 0..<visibleCount {
            try Task.checkCancellation()
            guard centralBytesRead + 46 <= UInt64(centralSize) else { throw PreviewFailure.damagedArchive(L10n.text("中央目录条目越界", "Central directory entry out of bounds")) }
            let fixed = try readExactly(handle, count: 46)
            guard fixed.u32(0) == centralSignature else { throw PreviewFailure.damagedArchive(L10n.text("中央目录条目无效", "Invalid central directory entry")) }
            let flags = fixed.u16(8)
            let method = fixed.u16(10)
            let modifiedTime = fixed.u16(12)
            let modifiedDate = fixed.u16(14)
            let compressed = UInt64(fixed.u32(20))
            let uncompressed = UInt64(fixed.u32(24))
            let nameLength = Int(fixed.u16(28))
            let extraLength = Int(fixed.u16(30))
            let commentLength = Int(fixed.u16(32))
            guard nameLength > 0 else { throw PreviewFailure.damagedArchive(L10n.text("存在空文件名", "An entry has an empty file name")) }
            let variableLength = nameLength + extraLength + commentLength
            centralBytesRead += 46 + UInt64(variableLength)
            guard centralBytesRead <= UInt64(centralSize) else { throw PreviewFailure.damagedArchive(L10n.text("中央目录条目越界", "Central directory entry out of bounds")) }
            guard compressed != UInt64(UInt32.max), uncompressed != UInt64(UInt32.max) else {
                throw PreviewFailure.unsupportedArchive(L10n.text("M2 暂不支持 ZIP64 条目", "ZIP64 entries are not supported yet"))
            }
            let nameData = try readExactly(handle, count: nameLength)
            _ = try readExactly(handle, count: extraLength + commentLength)
            let name = decodeName(nameData, utf8: flags & 0x0800 != 0)
            let encrypted = flags & 0x0001 != 0
            let unsafe = isUnsafePath(name)
            let folder = name.hasSuffix("/")
            let suspicious = !folder && uncompressed > 10 * 1024 * 1024 && (compressed == 0 || uncompressed / max(1, compressed) > 100)
            if encrypted { encryptedCount += 1 }
            if unsafe { unsafeCount += 1 }
            if suspicious { suspiciousCount += 1 }
            if folder { folderCount += 1 } else { fileCount += 1 }
            let addition = totalUncompressed.addingReportingOverflow(uncompressed)
            totalUncompressed = addition.overflow ? UInt64.max : addition.partialValue
            var notes: [String] = []
            if encrypted { notes.append(L10n.text("已加密", "Encrypted")) }
            if unsafe { notes.append(L10n.text("不安全路径", "Unsafe path")) }
            if suspicious { notes.append(L10n.text("异常压缩比", "Suspicious compression ratio")) }
            let note = notes.isEmpty ? "" : " · ⚠︎ " + notes.joined(separator: L10n.text("、", "; "))
            let size = folder ? "" : " · \(formatBytes(clampedInt64(uncompressed))) → \(formatBytes(clampedInt64(compressed)))"
            let modificationDate = dosDate(modifiedDate, modifiedTime)
            let date = modificationDate.map { " · \(formatDate($0))" } ?? ""
            rows.append("[\(folder ? L10n.text("文件夹", "Folder") : L10n.text("文件", "File"))] \(escape(name))\(size) · \(compressionName(method))\(date)\(note)")
            items.append(PreviewSnapshot.Item(path: escape(name), sourcePath: name,
                kind: folder ? .folder : .file,
                size: folder ? nil : clampedInt64(uncompressed),
                compressedSize: folder ? nil : clampedInt64(compressed),
                modificationDate: modificationDate, compression: compressionName(method), warnings: notes))
        }
        var warnings: [String] = []
        if count > visibleCount { warnings.append(L10n.text("仅显示前 \(visibleCount) 项", "Showing the first \(visibleCount) entries")) }
        if encryptedCount > 0 { warnings.append(L10n.text("\(encryptedCount) 项加密", "\(encryptedCount) encrypted")) }
        if unsafeCount > 0 { warnings.append(L10n.text("\(unsafeCount) 项路径不安全", "\(unsafeCount) unsafe paths")) }
        if suspiciousCount > 0 { warnings.append(L10n.text("\(suspiciousCount) 项压缩比异常", "\(suspiciousCount) suspicious compression ratios")) }
        let warningText = warnings.isEmpty ? "" : " · ⚠︎ " + warnings.joined(separator: L10n.text("、", "; "))
        return PreviewSnapshot(title: url.lastPathComponent,
            summary: L10n.text("SpaceLens · ZIP · \(L10n.count(folderCount, "个文件夹", "folder", "folders")) · \(L10n.count(fileCount, "个文件", "file", "files")) · 解压后 \(formatBytes(clampedInt64(totalUncompressed)))\(warningText)",
                              "SpaceLens · ZIP · \(L10n.count(folderCount, "个文件夹", "folder", "folders")) · \(L10n.count(fileCount, "个文件", "file", "files")) · \(formatBytes(clampedInt64(totalUncompressed))) unpacked\(warningText)"),
            body: rows.isEmpty ? L10n.text("这是一个空 ZIP。", "This is an empty ZIP.") : rows.joined(separator: "\n"),
            truncated: count > visibleCount, contentKind: .zip, items: items)
    }

    private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        if count == 0 { return Data() }
        guard count >= 0, let data = try handle.read(upToCount: count), data.count == count else { throw PreviewFailure.damagedArchive(L10n.text("文件意外结束", "Unexpected end of file")) }
        return data
    }
    private static func findEOCD(in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        for offset in stride(from: data.count - 4, through: 0, by: -1) {
            guard data.u32(offset) == eocdSignature, offset + 22 <= data.count else { continue }
            let commentLength = Int(data.u16(offset + 20))
            if offset + 22 + commentLength == data.count { return offset }
        }
        return nil
    }
    private static func decodeName(_ data: Data, utf8: Bool) -> String {
        if utf8, let value = String(data: data, encoding: .utf8) { return value }
        if let value = String(data: data, encoding: .utf8) { return value }
        return String(data: data, encoding: .isoLatin1) ?? L10n.text("<无法解码的文件名>", "<undecodable file name>")
    }
    private static func isUnsafePath(_ value: String) -> Bool {
        value.hasPrefix("/") || value.hasPrefix("\\") || value.contains("\0") ||
            value.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..") ||
            (value.count >= 2 && value[value.index(after: value.startIndex)] == ":")
    }
    private static func compressionName(_ method: UInt16) -> String {
        switch method {
        case 0: return L10n.text("未压缩", "Stored")
        case 8: return "Deflate"
        case 12: return "BZIP2"
        case 14: return "LZMA"
        case 93: return "Zstandard"
        case 99: return "AES"
        default: return L10n.text("压缩方法 \(method)", "Compression method \(method)")
        }
    }
    private static func dosDate(_ date: UInt16, _ time: UInt16) -> Date? {
        guard date != 0 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 1980 + Int((date >> 9) & 0x7f)
        components.month = Int((date >> 5) & 0x0f)
        components.day = Int(date & 0x1f)
        components.hour = Int((time >> 11) & 0x1f)
        components.minute = Int((time >> 5) & 0x3f)
        components.second = Int(time & 0x1f) * 2
        return components.date
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
    private static func clampedInt64(_ value: UInt64) -> Int64 {
        value > UInt64(Int64.max) ? Int64.max : Int64(value)
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 |
            UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
