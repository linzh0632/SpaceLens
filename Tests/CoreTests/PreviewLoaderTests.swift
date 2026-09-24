import XCTest
@testable import SpaceLensCore

final class PreviewLoaderTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func write(_ name: String, _ data: Data) throws -> URL {
        let url = directory.appendingPathComponent(name); try data.write(to: url); return url
    }
    func testUnicodeAndEmptyText() throws {
        let u = try write("中文.spacelens", Data("中文 👀".utf8))
        XCTAssertEqual(try PreviewLoader.load(u).body, "中文 👀")
        XCTAssertEqual(try PreviewLoader.load(write("empty.spacelens", Data())).body, "")
    }
    func testInvalidTextAndUnsupported() throws {
        XCTAssertThrowsError(try PreviewLoader.load(write("bad.spacelens", Data([0xff, 0xfe]))))
        XCTAssertThrowsError(try PreviewLoader.load(write("native.pdf", Data())))
    }
    func testBoundedReadHandlesSplitUnicode() throws {
        let value = String(repeating: "a", count: PreviewLoader.maximumBytes - 1) + "👀 trailing"
        let result = try PreviewLoader.load(write("big.spacelens", Data(value.utf8)))
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.body, String(repeating: "a", count: PreviewLoader.maximumBytes - 1))
    }
    func testInvalidInteriorUTF8IsNotSilentlyReplaced() throws {
        var data = Data([0xff]); data.append(Data(repeating: 65, count: PreviewLoader.maximumBytes + 1))
        XCTAssertThrowsError(try PreviewLoader.load(write("invalid.spacelens", data)))
    }
    func testDirectoryTreeAndLimit() throws {
        let nested = directory.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("must-not-be-visible"))
        let tree = try PreviewLoader.load(directory)
        XCTAssertEqual(tree.contentKind, .directory)
        XCTAssertEqual(tree.items.first(where: { $0.path == "nested" })?.kind, .folder)
        XCTAssertEqual(tree.items.first(where: { $0.path == "nested/must-not-be-visible" })?.kind, .file)
        XCTAssertTrue(tree.body.contains("  [文件] must-not-be-visible"))
        for n in 0..<5 { _ = try write("file-\(n)", Data()) }
        let limited = try PreviewLoader.load(directory, entryLimit: 5, depthLimit: PreviewLoader.maximumDepth)
        XCTAssertTrue(limited.truncated)
        XCTAssertEqual(limited.body.components(separatedBy: "\n").count, 5)
    }
    func testEmptyAndSymlinkDirectory() throws {
        XCTAssertEqual(try PreviewLoader.load(directory).body, "这是一个空文件夹。")
        let link = directory.appendingPathComponent("loop")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        XCTAssertTrue(try PreviewLoader.load(directory).body.contains("[链接] loop"))
        XCTAssertThrowsError(try PreviewLoader.load(link))
    }
    func testFilenameCannotInjectRows() throws {
        _ = try write("line\nbreak", Data())
        let preview = try PreviewLoader.load(directory)
        XCTAssertTrue(preview.body.contains("[文件] line\\nbreak"))
        XCTAssertFalse(preview.body.contains("line\nbreak"))
    }
    func testExactLimitIsNotTruncated() throws {
        let result = try PreviewLoader.load(write("exact.spacelens", Data(repeating: 65, count: PreviewLoader.maximumBytes)))
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.body.utf8.count, PreviewLoader.maximumBytes)
    }
    func testMissingFileReportsError() {
        XCTAssertThrowsError(try PreviewLoader.load(directory.appendingPathComponent("missing.spacelens")))
    }
    func testFIFOIsRejectedWithoutOpening() throws {
        let fifo = directory.appendingPathComponent("pipe.spacelens")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try PreviewLoader.load(fifo))
    }
    func testDeepDirectoryIsTruncated() throws {
        var current = directory!
        for depth in 1...PreviewLoader.maximumDepth + 2 {
            current.appendPathComponent("level-\(depth)")
            try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        }
        let result = try PreviewLoader.load(directory, entryLimit: PreviewLoader.maximumEntries, depthLimit: 3)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.summary.contains("最多 3 层"))
        XCTAssertFalse(result.body.contains("level-4"))
    }
    func testNormalZipMetadata() throws {
        let url = try writeZip("normal.zip", entries: [
            ZipEntry(name: "Folder/", compressed: 0, uncompressed: 0),
            ZipEntry(name: "Folder/中文.txt", compressed: 12, uncompressed: 20, flags: 0x0800)
        ])
        let result = try PreviewLoader.load(url)
        XCTAssertEqual(result.contentKind, .zip)
        XCTAssertEqual(result.items.map(\.path), ["Folder/", "Folder/中文.txt"])
        XCTAssertEqual(result.items.last?.compressedSize, 12)
        XCTAssertTrue(result.summary.contains("1 个文件夹 · 1 个文件"))
        XCTAssertTrue(result.body.contains("Folder/中文.txt"))
        XCTAssertTrue(result.body.contains("Deflate"))
    }
    func testZipWarnings() throws {
        let url = try writeZip("warnings.zip", entries: [
            ZipEntry(name: "../escape.txt", compressed: 1, uncompressed: 20_000_000, flags: 1)
        ])
        let result = try PreviewLoader.load(url)
        XCTAssertTrue(result.summary.contains("1 项加密"))
        XCTAssertTrue(result.summary.contains("1 项路径不安全"))
        XCTAssertTrue(result.summary.contains("1 项压缩比异常"))
    }
    func testZipLimitAndSignatureInsideComment() throws {
        let url = try writeZip("comment.zip", entries: [
            ZipEntry(name: "one.txt", compressed: 1, uncompressed: 1),
            ZipEntry(name: "two.txt", compressed: 1, uncompressed: 1)
        ], comment: Data([0x50, 0x4b, 0x05, 0x06]))
        let result = try PreviewLoader.load(url, entryLimit: 1, depthLimit: PreviewLoader.maximumDepth)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.summary.contains("仅显示前 1 项"))
    }
    func testZip64EntryIsExplicitlyUnsupported() throws {
        let url = try writeZip("zip64.zip", entries: [
            ZipEntry(name: "huge.bin", compressed: UInt32.max, uncompressed: UInt32.max)
        ], includeLocalPayload: false)
        XCTAssertThrowsError(try PreviewLoader.load(url)) { error in
            XCTAssertTrue(error.localizedDescription.contains("ZIP64"))
        }
    }
    func testEmptyAndDamagedZip() throws {
        let empty = try writeZip("empty.zip", entries: [])
        XCTAssertEqual(try PreviewLoader.load(empty).body, "这是一个空 ZIP。")
        let damaged = try write("damaged.zip", Data("not a zip".utf8))
        XCTAssertThrowsError(try PreviewLoader.load(damaged)) { error in
            XCTAssertTrue(error.localizedDescription.contains("损坏"))
        }
    }
    func testCommonTextAndCodeClassification() throws {
        let text = try PreviewLoader.load(write("notes.txt", Data("hello\nworld".utf8)))
        XCTAssertEqual(text.contentKind, .text)
        XCTAssertTrue(text.summary.contains("2 行"))
        let code = try PreviewLoader.load(write("main.swift", Data("let value = 42".utf8)))
        XCTAssertEqual(code.contentKind, .code)
        XCTAssertEqual(code.language, "SWIFT")
    }
    func testUTF16TextAndInvalidEncoding() throws {
        var utf16 = Data([0xff, 0xfe])
        utf16.append("你好".data(using: .utf16LittleEndian)!)
        XCTAssertEqual(try PreviewLoader.load(write("utf16.txt", utf16)).body, "你好")
        XCTAssertThrowsError(try PreviewLoader.load(write("invalid.txt", Data([0xff, 0x00, 0xff]))))
    }
    func testMarkdownClassification() throws {
        let result = try PreviewLoader.load(write("README.md", Data("# Title\n\n- item".utf8)))
        XCTAssertEqual(result.contentKind, .markdown)
        XCTAssertEqual(result.language, "Markdown")
    }
    func testCSVQuotedCellsAndMissingValues() throws {
        let value = "name,note,age\nAda,\"hello, world\",36\nBob,,40\n"
        let result = try PreviewLoader.load(write("people.csv", Data(value.utf8)))
        XCTAssertEqual(result.contentKind, .table)
        XCTAssertEqual(result.table?.columns, ["name", "note", "age"])
        XCTAssertEqual(result.table?.rows.first, ["Ada", "hello, world", "36"])
        XCTAssertEqual(result.table?.rows.last, ["Bob", "", "40"])
    }
    func testJSONAndJSONLinesStructure() throws {
        let json = try PreviewLoader.load(write("sample.json", Data("{\"name\":\"SpaceLens\",\"enabled\":true,\"items\":[1,2]}".utf8)))
        XCTAssertEqual(json.contentKind, .structured)
        XCTAssertEqual(json.structuredItems.first?.type, "对象")
        XCTAssertEqual(json.structuredItems.first?.children.map(\.key), ["enabled", "items", "name"])
        let jsonl = try PreviewLoader.load(write("sample.jsonl", Data("{\"id\":1}\n{\"id\":2}".utf8)))
        XCTAssertEqual(jsonl.structuredItems.count, 2)
    }
    func testMalformedCSVAndJSONAreExplicit() throws {
        XCTAssertThrowsError(try PreviewLoader.load(write("bad.csv", Data("a,b\n\"open,b".utf8))))
        XCTAssertThrowsError(try PreviewLoader.load(write("bad.json", Data("{oops}".utf8)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("JSON 格式错误"))
        }
    }
    func testCommonTextReadIsBounded() throws {
        let data = Data(repeating: 65, count: PreviewLoader.maximumTextBytes + 1)
        let result = try PreviewLoader.load(write("large.log", data))
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.body.utf8.count, PreviewLoader.maximumTextBytes)
    }
    func testTableAndJSONNodeLimits() throws {
        let csv = "value\n" + (0..<1_002).map(String.init).joined(separator: "\n")
        let table = try PreviewLoader.load(write("large.csv", Data(csv.utf8)))
        XCTAssertEqual(table.table?.rows.count, 1_000)
        XCTAssertEqual(table.table?.omittedRowCount, 2)
        XCTAssertTrue(table.truncated)

        let json = "[" + (0..<10_050).map(String.init).joined(separator: ",") + "]"
        let tree = try PreviewLoader.load(write("large.json", Data(json.utf8)))
        XCTAssertEqual(tree.structuredItems.first?.children.count, 9_999)
        XCTAssertTrue(tree.truncated)
    }
    func testCancellation() async throws {
        let url = try write("cancel.spacelens", Data("test".utf8))
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try PreviewLoader.load(url)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

private struct ZipEntry {
    let name: String
    let compressed: UInt32
    let uncompressed: UInt32
    var flags: UInt16 = 0
}

private extension PreviewLoaderTests {
    func writeZip(_ name: String, entries: [ZipEntry], comment: Data = Data(), includeLocalPayload: Bool = true) throws -> URL {
        var local = Data()
        var central = Data()
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let localOffset = UInt32(local.count)
            local.appendLE(UInt32(0x0403_4b50)); local.appendLE(UInt16(20)); local.appendLE(entry.flags)
            local.appendLE(UInt16(8)); local.appendLE(UInt16(0)); local.appendLE(UInt16(0)); local.appendLE(UInt32(0))
            local.appendLE(entry.compressed); local.appendLE(entry.uncompressed); local.appendLE(UInt16(nameData.count))
            local.appendLE(UInt16(0)); local.append(nameData)
            if includeLocalPayload { local.append(Data(repeating: 0, count: Int(entry.compressed))) }

            central.appendLE(UInt32(0x0201_4b50)); central.appendLE(UInt16(20)); central.appendLE(UInt16(20))
            central.appendLE(entry.flags); central.appendLE(UInt16(8)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt32(0)); central.appendLE(entry.compressed); central.appendLE(entry.uncompressed)
            central.appendLE(UInt16(nameData.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0)); central.appendLE(localOffset)
            central.append(nameData)
        }
        var archive = local
        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.appendLE(UInt32(0x0605_4b50)); archive.appendLE(UInt16(0)); archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count)); archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt32(central.count)); archive.appendLE(centralOffset); archive.appendLE(UInt16(comment.count))
        archive.append(comment)
        return try write(name, archive)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
