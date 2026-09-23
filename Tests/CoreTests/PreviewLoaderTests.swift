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
    func testDirectoryLimitAndNoRecursion() throws {
        let nested = directory.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("must-not-be-visible"))
        let shallow = try PreviewLoader.load(directory)
        XCTAssertFalse(shallow.body.contains("must-not-be-visible"))
        for n in 0..<105 { _ = try write("file-\(n)", Data()) }
        let limited = try PreviewLoader.load(directory)
        XCTAssertTrue(limited.truncated)
        XCTAssertEqual(limited.body.components(separatedBy: "\n").count, PreviewLoader.maximumEntries)
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
        XCTAssertEqual(preview.body, "[文件] line\\nbreak")
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
