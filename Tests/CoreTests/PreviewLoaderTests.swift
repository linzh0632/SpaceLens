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
    func testTarMetadataWarningsAndLimit() throws {
        let data = makeTar([
            TarEntry(name: "Folder/", folder: true),
            TarEntry(name: "Folder/hello.txt", payload: Data("hello SpaceLens\n".utf8)),
            TarEntry(name: "../escape.txt", payload: Data("unsafe".utf8))
        ])
        let result = try PreviewLoader.load(write("sample.tar", data))
        XCTAssertEqual(result.contentKind, .archive)
        XCTAssertEqual(result.items.map(\.path), ["Folder/", "Folder/hello.txt", "../escape.txt"])
        XCTAssertTrue(result.summary.contains("1 个文件夹 · 2 个文件"))
        XCTAssertTrue(result.summary.contains("1 项路径不安全"))
        XCTAssertEqual(result.items[1].size, 16)

        let limited = try PreviewLoader.load(write("limited.tar", data), entryLimit: 1,
                                             depthLimit: PreviewLoader.maximumDepth)
        XCTAssertTrue(limited.truncated)
        XCTAssertEqual(limited.items.count, 1)
        XCTAssertTrue(limited.summary.contains("仅显示前 1 项"))
    }
    func testCompressedTarFamilies() throws {
        let fixtures: [(String, String, String)] = [
            ("sample.tgz", "H4sIAAAAAAAC/+3RMQoCMRBA0ak9RU6gyZBsbrCVnSdYNGARXNmN4PENsVuwjCD+18wwzRR/nPMlLQfpyVYxhDar7Wy780F9jNa3e1RVMUG+4LGWaakv5T+N7/7XlPO8L8/Sq//g/ef+uunvnA2DGEv/7lp4c7pP53RMt3UnAAAAAAAAAAAAAAAAAH7GC3WCBjkAKAAA", "GZIP"),
            ("sample.tbz2", "QlpoOTFBWSZTWTIIitQAAI1/gMqQQABAAfeAAQRIIG5F3kAICCAAkglRMho0AAA0aNBJKG1MSHoQ0DQZNH7WdNysSAk6SEX00MI3BI3soiEMLWpaETCATYCBMqAOnawDIygzVlvJoUJOXxHLncllVMoVEsxg5bEo90OnnbxzxvWpSMEpOzxos9+IOPoF2AhAfi7kinChIGQRFag=", "BZIP2"),
            ("sample.txz", "/Td6WFoAAATm1rRGAgAhARYAAAB0L+Wj4Cf/AIhdACMbyYZYRyBGQoRqcSuY+NILyi35hoL+pVVXfn/g1zx21CvvIgNK7qm3LbMFQfynH/gj8xr6b55FnbMlfeQJAtng8mpEXk8KaSwa8SaAqWmB0JKYXDakeEC1+HJ4czBaAqg/ujkvqRJPBfkMwEnX32xD6zuB1R13XPHn4ZA7D19x+1H/vXqj1AwAiW+xKVfy7d4AAaQBgFAAAB42Xf2xxGf7AgAAAAAEWVo=", "XZ")
        ]
        for (name, encoded, filter) in fixtures {
            let result = try PreviewLoader.load(write(name, Data(base64Encoded: encoded)!))
            XCTAssertEqual(result.contentKind, .archive, name)
            XCTAssertEqual(result.items.map(\.path), ["Folder/", "Folder/hello.txt"], name)
            XCTAssertTrue(result.body.contains(filter), name)
        }
    }
    func testStandaloneGzip() throws {
        let encoded = "H4sIAAAAAAAC/ysuScxLSczJz0tVSK/KLOACANugwj0QAAAA"
        let result = try PreviewLoader.load(write("plain.txt.gz", Data(base64Encoded: encoded)!))
        XCTAssertEqual(result.contentKind, .archive)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertNil(result.items.first?.size)
        XCTAssertTrue(result.body.contains("GZIP"))
    }
    func testDamagedTarIsExplicit() throws {
        XCTAssertThrowsError(try PreviewLoader.load(write("broken.tar", Data("not an archive".utf8)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("归档文件已损坏"))
        }
    }
    func testXMLAndBinaryPropertyLists() throws {
        let value: [String: Any] = [
            "enabled": true,
            "items": ["one", "two"],
            "limits": ["rows": 100],
            "payload": Data([0x00, 0x01, 0x02]),
            "created": Date(timeIntervalSince1970: 1_700_000_000)
        ]
        for (name, format) in [("Config.plist", PropertyListSerialization.PropertyListFormat.xml),
                               ("Binary.plist", .binary)] {
            let data = try PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0)
            let result = try PreviewLoader.load(write(name, data))
            XCTAssertEqual(result.contentKind, .structured, name)
            XCTAssertEqual(result.structuredItems.first?.type, "字典", name)
            XCTAssertEqual(result.structuredItems.first?.children.map(\.key),
                           ["created", "enabled", "items", "limits", "payload"], name)
            XCTAssertTrue(result.summary.contains(format == .binary ? "Binary plist" : "XML plist"), name)
        }
    }
    func testMalformedPropertyListIsExplicit() throws {
        XCTAssertThrowsError(try PreviewLoader.load(write("broken.plist", Data("<plist>".utf8)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("属性列表格式错误"))
        }
    }
    func testSQLiteSchemaRowsAndReadOnlyLimits() throws {
        let url = try makeSQLite("Sample.sqlite", statements: [
            "CREATE TABLE people(id INTEGER PRIMARY KEY, name TEXT NOT NULL, payload BLOB)",
            "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<105) INSERT INTO people(name,payload) SELECT 'person-'||x, x'0001' FROM n",
            "CREATE TABLE \"odd\"\"name\"(\"value\" TEXT)",
            "INSERT INTO \"odd\"\"name\" VALUES ('quoted identifier')"
        ])
        let result = try PreviewLoader.load(url)
        XCTAssertEqual(result.contentKind, .database)
        XCTAssertEqual(result.structuredItems.map(\.key), ["odd\"name", "people"])
        let people = result.structuredItems.first { $0.key == "people" }
        XCTAssertEqual(people?.children.first?.children.count, 3)
        XCTAssertEqual(people?.children.last?.children.count, 100)
        XCTAssertTrue(people?.children.last?.type.contains("仅显示前 100 行") == true)
        XCTAssertTrue(result.truncated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + "-journal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + "-wal"))
    }
    func testEmptyAndDamagedSQLite() throws {
        let empty = try makeSQLite("Empty.db", statements: [])
        XCTAssertTrue(try PreviewLoader.load(empty).structuredItems.isEmpty)
        XCTAssertThrowsError(try PreviewLoader.load(write("Broken.sqlite3", Data("not sqlite".utf8)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("SQLite 数据库无法读取"))
        }
    }
    func testExtendedMarkdownDocumentFormats() throws {
        let fixtures: [(String, String)] = [
            ("component.mdx", "MDX"),
            ("report.qmd", "Quarto Markdown"),
            ("analysis.rmd", "R Markdown")
        ]
        for (name, format) in fixtures {
            let result = try PreviewLoader.load(write(name, Data("# 标题\n\n正文".utf8)))
            XCTAssertEqual(result.contentKind, .markdown, name)
            XCTAssertTrue(result.summary.contains(format), name)
            XCTAssertEqual(result.body, "# 标题\n\n正文", name)
        }
    }
    func testRSTAsciiDocAndTeXNormalization() throws {
        let rst = try PreviewLoader.load(write("guide.rst", Data("标题\n====\n\n.. code-block:: swift\n\n   let value = 42\n\n正文".utf8)))
        XCTAssertTrue(rst.body.contains("# 标题"))
        XCTAssertTrue(rst.body.contains("```swift"))
        XCTAssertTrue(rst.body.contains("let value = 42"))

        let adoc = try PreviewLoader.load(write("guide.adoc", Data("= 标题\n\n[source,swift]\n----\nlet value = 42\n----".utf8)))
        XCTAssertTrue(adoc.body.contains("# 标题"))
        XCTAssertTrue(adoc.body.contains("```swift"))

        let tex = try PreviewLoader.load(write("paper.tex", Data("\\section{方法}\n\\begin{verbatim}\nraw <code>\n\\end{verbatim}".utf8)))
        XCTAssertTrue(tex.body.contains("# 方法"))
        XCTAssertTrue(tex.body.contains("```text"))
        XCTAssertTrue(tex.body.contains("raw <code>"))
    }
    func testJupyterNotebookRendersCellsWithoutExecution() throws {
        let notebook: [String: Any] = [
            "nbformat": 4,
            "metadata": ["language_info": ["name": "python"]],
            "cells": [
                ["cell_type": "markdown", "source": ["# Notebook\n", "本地预览"]],
                ["cell_type": "code", "source": ["print('hello')"], "outputs": [
                    ["output_type": "stream", "text": ["hello\n"]],
                    ["output_type": "display_data", "data": ["image/png": "ignored", "text/plain": ["<Figure 1>"]]]
                ]],
                ["cell_type": "raw", "source": "raw content"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: notebook)
        let result = try PreviewLoader.load(write("Notebook.ipynb", data))
        XCTAssertEqual(result.contentKind, .markdown)
        XCTAssertTrue(result.summary.contains("3 个单元格"))
        XCTAssertTrue(result.body.contains("```python"))
        XCTAssertTrue(result.body.contains("print('hello')"))
        XCTAssertTrue(result.body.contains("hello"))
        XCTAssertTrue(result.body.contains("<Figure 1>"))
        XCTAssertFalse(result.body.contains("ignored"))
    }
    func testNotebookLimitsAndMalformedInput() throws {
        let cells = (0..<205).map { ["cell_type": "markdown", "source": "cell-\($0)"] }
        let data = try JSONSerialization.data(withJSONObject: ["nbformat": 4, "cells": cells])
        let limited = try PreviewLoader.load(write("Large.ipynb", data))
        XCTAssertTrue(limited.truncated)
        XCTAssertTrue(limited.summary.contains("仅显示前 200 个单元格"))
        XCTAssertFalse(limited.body.contains("cell-204"))
        XCTAssertThrowsError(try PreviewLoader.load(write("Broken.ipynb", Data("{}".utf8)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Jupyter Notebook 格式错误"))
        }
    }
    func testMermaidFlowchartRendersEscapedSVG() throws {
        let source = "flowchart TD\nA[开始] --> B{检查 <script>}\nB -->|成功| C(完成)"
        let result = try PreviewLoader.load(write("Flow.mmd", Data(source.utf8)))
        XCTAssertEqual(result.contentKind, .diagram)
        XCTAssertTrue(result.summary.contains("Mermaid"))
        XCTAssertTrue(result.diagramSVG?.contains("开始") == true)
        XCTAssertTrue(result.diagramSVG?.contains("&lt;script&gt;") == true)
        XCTAssertFalse(result.diagramSVG?.contains("<script>") == true)
        XCTAssertTrue(result.diagramSVG?.contains("成功") == true)
    }
    func testMermaidAndPlantUMLSequenceDiagrams() throws {
        let mermaid = try PreviewLoader.load(write("Sequence.mermaid", Data("sequenceDiagram\nparticipant Alice\nAlice->>Bob: Hello".utf8)))
        XCTAssertEqual(mermaid.contentKind, .diagram)
        XCTAssertTrue(mermaid.diagramSVG?.contains("Alice") == true)
        XCTAssertTrue(mermaid.diagramSVG?.contains("Bob") == true)
        XCTAssertTrue(mermaid.diagramSVG?.contains("Hello") == true)

        let plant = try PreviewLoader.load(write("Sequence.puml", Data("@startuml\nAlice -> Bob: Request\nBob --> Alice: Response\n@enduml".utf8)))
        XCTAssertEqual(plant.contentKind, .diagram)
        XCTAssertTrue(plant.summary.contains("PlantUML"))
        XCTAssertTrue(plant.diagramSVG?.contains("Request") == true)
        XCTAssertTrue(plant.diagramSVG?.contains("Response") == true)
    }
    func testUncompressedDrawIORendersShapesAndEdges() throws {
        let source = #"<mxfile><diagram compressed="false"><mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/><mxCell id="a" value="开始" style="ellipse" vertex="1" parent="1"><mxGeometry x="20" y="30" width="120" height="60" as="geometry"/></mxCell><mxCell id="b" value="结束" vertex="1" parent="1"><mxGeometry x="260" y="30" width="120" height="60" as="geometry"/></mxCell><mxCell id="e" value="下一步" edge="1" source="a" target="b" parent="1"><mxGeometry relative="1" as="geometry"/></mxCell></root></mxGraphModel></diagram></mxfile>"#
        let result = try PreviewLoader.load(write("Flow.drawio", Data(source.utf8)))
        XCTAssertEqual(result.contentKind, .diagram)
        XCTAssertTrue(result.summary.contains("Draw.io"))
        XCTAssertTrue(result.diagramSVG?.contains("<ellipse") == true)
        XCTAssertTrue(result.diagramSVG?.contains("下一步") == true)
    }
    func testDiagramErrorsAreExplicit() throws {
        XCTAssertThrowsError(try PreviewLoader.load(write("Broken.mmd", Data("pie\nA: 1".utf8)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("图表格式错误"))
        }
        let compressed = #"<mxfile><diagram>ZY8xDsMgDEWvgnwBklRqF8iSIVMPgYQVkKAgQxty%2BzpKF9TJ3%2F5%2B%2BraKbSWT3TNZDLOilOqsYlswBOGthgFk148gsiF81X9rAvEx4Y0alhQzYSloeYRUsXXgCCe3YopY6RBsTgOIQ8ONy%2B5tdbxzZ%2B3Qb46BB2tTNGw%2F5AyWVzKL62bZPfIF</diagram></mxfile>"#
        let decoded = try PreviewLoader.load(write("Compressed.drawio", Data(compressed.utf8)))
        XCTAssertEqual(decoded.contentKind, .diagram)
        XCTAssertTrue(decoded.diagramSVG?.contains("Compressed") == true)
        XCTAssertThrowsError(try PreviewLoader.load(write("Broken.drawio", Data(#"<mxfile><diagram>not-valid</diagram></mxfile>"#.utf8)))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Base64") || error.localizedDescription.contains("损坏"))
        }
    }
    func testColumnarDataFixtures() throws {
        let fixtures: [(String, String)] = [
            ("People.parquet", "UEFSMRUEFRgVHEwVBhUAEgAADCwBAAAAAgAAAAMAAAAVABUUFRgsFQYVEBUGFQYcGAQDAAAAGAQBAAAAFgAoBAMAAAAYBAEAAAAAAAAKJAIAAAAGAQIDJAAVBBU0FThMFQYVABIAABpkAwAAAEFkYQYAAADmnpflpoIFAAAAR3JhY2UVABUUFRgsFQYVEBUGFQYcNgAoBuael+WmghgDQWRhAAAACiQCAAAABgECAyQAFQQVIBUkTBUEFQASAAAQPAAAAAAAoFhAAAAAAAAAWUAVABUSFRYsFQYVEBUGFQYcGAgAAAAAAABZQBgIAAAAAACgWEAWAigIAAAAAAAAWUAYCAAAAAAAoFhAAAAACSACAAAAAwUBAwIVABUOFRIsFQYVABUGFQYcGAEBGAEAFgAoAQEYAQAAAAAHGAIAAAAGAQUVBBlcNQAYBnNjaGVtYRUIABUCJQIYAmlkABUMJQIYBG5hbWUlAEwcAAAAFQolAhgFc2NvcmUAFQAlAhgGYWN0aXZlABYGGRwZTCYAHBUCGTUABhAZGAJpZBUCFgYWogEWqgEmQCYIHBgEAwAAABgEAQAAABYAKAQDAAAAGAQBAAAAABksFQQVABUCABUAFRAVAgA8KQYZJgAGAAAAJgAcFQwZNQAGEBkYBG5hbWUVAhYGFqgBFrABJoYCJrIBHDYAKAbmnpflpoIYA0FkYQAZLBUEFQAVAgAVABUQFQIAPBYcGQYZJgAGAAAAJgAcFQoZNQAGEBkYBXNjb3JlFQIWBhbIARbQASaiAybiAhwYCAAAAAAAAFlAGAgAAAAAAKBYQBYCKAgAAAAAAABZQBgIAAAAAACgWEAAGSwVBBUAFQIAFQAVEBUCADwpBhkmAgQAAAAmABwVABklBgAZGAZhY3RpdmUVAhYGFlAWVCayBDwYAQEYAQAWACgBARgBAAAZHBUAFQAVAgA8KQYZJgAGAAAAFuIEFgYmCBb+BAAZHBgMQVJST1c6c2NoZW1hGOwCLy8vLy93Z0JBQUFRQUFBQUFBQUtBQXdBQmdBRkFBZ0FDZ0FBQUFBQkJBQU1BQUFBQ0FBSUFBQUFCQUFJQUFBQUJBQUFBQVFBQUFDa0FBQUFaQUFBQURBQUFBQUVBQUFBZlAvLy93QUFBUVlRQUFBQUdBQUFBQVFBQUFBQUFBQUFCZ0FBQUdGamRHbDJaUUFBcVAvLy82VC8vLzhBQUFFREVBQUFBQndBQUFBRUFBQUFBQUFBQUFVQUFBQnpZMjl5WlFBR0FBZ0FCZ0FHQUFBQUFBQUNBTlQvLy84QUFBRUZFQUFBQUJ3QUFBQUVBQUFBQUFBQUFBUUFBQUJ1WVcxbEFBQUFBQVFBQkFBRUFBQUFFQUFVQUFnQUJnQUhBQXdBQUFBUUFCQUFBQUFBQUFFQ0VBQUFBQndBQUFBRUFBQUFBQUFBQUFJQUFBQnBaQUFBQ0FBTUFBZ0FCd0FJQUFBQUFBQUFBU0FBQUFBPQAYIHBhcnF1ZXQtY3BwLWFycm93IHZlcnNpb24gMjEuMC4wGUwcAAAcAAAcAAAcAAAATwMAAFBBUjE="),
            ("People.arrow", "QVJST1cxAAD/////CAEAABAAAAAAAAoADAAGAAUACAAKAAAAAAEEAAwAAAAIAAgAAAAEAAgAAAAEAAAABAAAAKQAAABkAAAAMAAAAAQAAAB8////AAABBhAAAAAYAAAABAAAAAAAAAAGAAAAYWN0aXZlAACo////pP///wAAAQMQAAAAHAAAAAQAAAAAAAAABQAAAHNjb3JlAAYACAAGAAYAAAAAAAIA1P///wAAAQUQAAAAHAAAAAQAAAAAAAAABAAAAG5hbWUAAAAABAAEAAQAAAAQABQACAAGAAcADAAAABAAEAAAAAAAAQIQAAAAHAAAAAQAAAAAAAAAAgAAAGlkAAAIAAwACAAHAAgAAAAAAAABIAAAAP////8oAQAAFAAAAAAAAAAMABYABgAFAAgADAAMAAAAAAMEABgAAABYAAAAAAAAAAAACgAYAAwABAAIAAoAAACsAAAAEAAAAAMAAAAAAAAAAAAAAAkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAABAAAAAAAAAAIAAAAAAAAAAOAAAAAAAAADAAAAAAAAAAAQAAAAAAAAA4AAAAAAAAABgAAAAAAAAAUAAAAAAAAAAAAAAAAAAAAFAAAAAAAAAAAQAAAAAAAAAAAAAABAAAAAMAAAAAAAAAAAAAAAAAAAADAAAAAAAAAAAAAAAAAAAAAwAAAAAAAAABAAAAAAAAAAMAAAAAAAAAAAAAAAAAAAABAAAAAgAAAAMAAAAAAAAAAAAAAAMAAAAJAAAADgAAAEFkYeael+WmgkdyYWNlAAAFAAAAAAAAAAAAAAAAoFhAAAAAAAAAAAAAAAAAAABZQAUAAAAAAAAA/////wAAAAAQAAAADAAUAAYACAAMABAADAAAAAAABAA0AAAAJAAAAAQAAAABAAAAGAEAAAAAAAAwAQAAAAAAAFgAAAAAAAAAAAAAAAgACAAAAAQACAAAAAQAAAAEAAAApAAAAGQAAAAwAAAABAAAAHz///8AAAEGEAAAABgAAAAEAAAAAAAAAAYAAABhY3RpdmUAAKj///+k////AAABAxAAAAAcAAAABAAAAAAAAAAFAAAAc2NvcmUABgAIAAYABgAAAAAAAgDU////AAABBRAAAAAcAAAABAAAAAAAAAAEAAAAbmFtZQAAAAAEAAQABAAAABAAFAAIAAYABwAMAAAAEAAQAAAAAAABAhAAAAAcAAAABAAAAAAAAAACAAAAaWQAAAgADAAIAAcACAAAAAAAAAEgAAAAMAEAAEFSUk9XMQ=="),
            ("People.feather", "QVJST1cxAAD/////CAEAABAAAAAAAAoADAAGAAUACAAKAAAAAAEEAAwAAAAIAAgAAAAEAAgAAAAEAAAABAAAAKQAAABkAAAAMAAAAAQAAAB8////AAABBhAAAAAYAAAABAAAAAAAAAAGAAAAYWN0aXZlAACo////pP///wAAAQMQAAAAHAAAAAQAAAAAAAAABQAAAHNjb3JlAAYACAAGAAYAAAAAAAIA1P///wAAAQUQAAAAHAAAAAQAAAAAAAAABAAAAG5hbWUAAAAABAAEAAQAAAAQABQACAAGAAcADAAAABAAEAAAAAAAAQIQAAAAHAAAAAQAAAAAAAAAAgAAAGlkAAAIAAwACAAHAAgAAAAAAAABIAAAAP////8oAQAAFAAAAAAAAAAMABYABgAFAAgADAAMAAAAAAMEABgAAABYAAAAAAAAAAAACgAYAAwABAAIAAoAAACsAAAAEAAAAAMAAAAAAAAAAAAAAAkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAABAAAAAAAAAAIAAAAAAAAAAOAAAAAAAAADAAAAAAAAAAAQAAAAAAAAA4AAAAAAAAABgAAAAAAAAAUAAAAAAAAAAAAAAAAAAAAFAAAAAAAAAAAQAAAAAAAAAAAAAABAAAAAMAAAAAAAAAAAAAAAAAAAADAAAAAAAAAAAAAAAAAAAAAwAAAAAAAAABAAAAAAAAAAMAAAAAAAAAAAAAAAAAAAABAAAAAgAAAAMAAAAAAAAAAAAAAAMAAAAJAAAADgAAAEFkYeael+WmgkdyYWNlAAAFAAAAAAAAAAAAAAAAoFhAAAAAAAAAAAAAAAAAAABZQAUAAAAAAAAA/////wAAAAAQAAAADAAUAAYACAAMABAADAAAAAAABAA0AAAAJAAAAAQAAAABAAAAGAEAAAAAAAAwAQAAAAAAAFgAAAAAAAAAAAAAAAgACAAAAAQACAAAAAQAAAAEAAAApAAAAGQAAAAwAAAABAAAAHz///8AAAEGEAAAABgAAAAEAAAAAAAAAAYAAABhY3RpdmUAAKj///+k////AAABAxAAAAAcAAAABAAAAAAAAAAFAAAAc2NvcmUABgAIAAYABgAAAAAAAgDU////AAABBRAAAAAcAAAABAAAAAAAAAAEAAAAbmFtZQAAAAAEAAQABAAAABAAFAAIAAYABwAMAAAAEAAQAAAAAAABAhAAAAAcAAAABAAAAAAAAAACAAAAaWQAAAgADAAIAAcACAAAAAAAAAEgAAAAMAEAAEFSUk9XMQ=="),
            ("People.avro", "T2JqAQQUYXZyby5jb2RlYw5kZWZsYXRlFmF2cm8uc2NoZW1htAN7InR5cGUiOiAicmVjb3JkIiwgIm5hbWUiOiAiUGVyc29uIiwgImZpZWxkcyI6IFt7Im5hbWUiOiAiaWQiLCAidHlwZSI6ICJpbnQifSwgeyJuYW1lIjogIm5hbWUiLCAidHlwZSI6ICJzdHJpbmcifSwgeyJuYW1lIjogInNjb3JlIiwgInR5cGUiOiBbIm51bGwiLCAiZG91YmxlIl0sICJkZWZhdWx0IjogbnVsbH0sIHsibmFtZSI6ICJhY3RpdmUiLCAidHlwZSI6ICJib29sZWFuIn1dfQD4LHbArGA1uV6TvuUjqu41BlJjYnNMSWRiAIEFEQ6MLDzP5k1/uqyJgYGNy70oMTkVIsUQ6cAIAMl2CfgsdsCsYDW5XpO+5SOq7jU="),
            ("People-Null.avro", "T2JqAQQUYXZyby5jb2RlYwhudWxsFmF2cm8uc2NoZW1htAN7InR5cGUiOiAicmVjb3JkIiwgIm5hbWUiOiAiUGVyc29uIiwgImZpZWxkcyI6IFt7Im5hbWUiOiAiaWQiLCAidHlwZSI6ICJpbnQifSwgeyJuYW1lIjogIm5hbWUiLCAidHlwZSI6ICJzdHJpbmcifSwgeyJuYW1lIjogInNjb3JlIiwgInR5cGUiOiBbIm51bGwiLCAiZG91YmxlIl0sICJkZWZhdWx0IjogbnVsbH0sIHsibmFtZSI6ICJhY3RpdmUiLCAidHlwZSI6ICJib29sZWFuIn1dfQDegHekp+pbzSPqkx8yqXK+BlQCBkFkYQIAAAAAAKBYQAEEDOael+WmggAABgpHcmFjZQIAAAAAAABZQAHegHekp+pbzSPqkx8yqXK+")
        ]
        var results: [String: PreviewSnapshot] = [:]
        for (name, encoded) in fixtures {
            do { results[name] = try PreviewLoader.load(write(name, Data(base64Encoded: encoded)!)) }
            catch { XCTFail("\(name): \(error.localizedDescription)"); continue }
        }
        let parquet = try XCTUnwrap(results["People.parquet"])
        XCTAssertEqual(parquet.contentKind, .table)
        XCTAssertTrue(parquet.summary.contains("3 行 · 4 列 · 1 个行组"))
        XCTAssertEqual(parquet.table?.rows.map { $0[0] }, ["id", "name", "score", "active"])
        XCTAssertTrue(parquet.body.contains("parquet-cpp-arrow"))
        for name in ["People.arrow", "People.feather"] {
            let result = try XCTUnwrap(results[name])
            XCTAssertEqual(result.table?.columns, ["id", "name", "score", "active"])
            XCTAssertEqual(result.table?.rows.count, 3)
            XCTAssertEqual(result.table?.rows[1][1], "林如")
            XCTAssertEqual(result.table?.rows[1][2], "NULL")
            XCTAssertFalse(result.truncated)
        }
        for name in ["People.avro", "People-Null.avro"] {
            let result = try XCTUnwrap(results[name])
            XCTAssertEqual(result.table?.columns, ["id", "name", "score", "active"])
            XCTAssertEqual(result.table?.rows.count, 3)
            XCTAssertEqual(result.table?.rows[1], ["2", "林如", "NULL", "false"])
        }
    }
    func testColumnarRowLimitAndNestedArrowFallback() throws {
        let largeArrow = try PreviewLoader.load(write("Large.arrow", Data(base64Encoded: "QVJST1cxAAD/////qAAAABAAAAAAAAoADAAGAAUACAAKAAAAAAEEAAwAAAAIAAgAAAAEAAgAAAAEAAAAAgAAAEQAAAAEAAAA1P///wAAAQUQAAAAHAAAAAQAAAAAAAAABAAAAG5hbWUAAAAABAAEAAQAAAAQABQACAAGAAcADAAAABAAEAAAAAAAAQIQAAAAHAAAAAQAAAAAAAAAAgAAAGlkAAAIAAwACAAHAAgAAAAAAAABIAAAAP/////IAAAAFAAAAAAAAAAMABYABgAFAAgADAAMAAAAAAMEABgAAACoBgAAAAAAAAAACgAYAAwABAAIAAoAAABsAAAAEAAAAHgAAAAAAAAAAAAAAAUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADgAQAAAAAAAOABAAAAAAAAAAAAAAAAAADgAQAAAAAAAOQBAAAAAAAAyAMAAAAAAADaAgAAAAAAAAAAAAACAAAAeAAAAAAAAAAAAAAAAAAAAHgAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAIAAAADAAAABAAAAAUAAAAGAAAABwAAAAgAAAAJAAAACgAAAAsAAAAMAAAADQAAAA4AAAAPAAAAEAAAABEAAAASAAAAEwAAABQAAAAVAAAAFgAAABcAAAAYAAAAGQAAABoAAAAbAAAAHAAAAB0AAAAeAAAAHwAAACAAAAAhAAAAIgAAACMAAAAkAAAAJQAAACYAAAAnAAAAKAAAACkAAAAqAAAAKwAAACwAAAAtAAAALgAAAC8AAAAwAAAAMQAAADIAAAAzAAAANAAAADUAAAA2AAAANwAAADgAAAA5AAAAOgAAADsAAAA8AAAAPQAAAD4AAAA/AAAAQAAAAEEAAABCAAAAQwAAAEQAAABFAAAARgAAAEcAAABIAAAASQAAAEoAAABLAAAATAAAAE0AAABOAAAATwAAAFAAAABRAAAAUgAAAFMAAABUAAAAVQAAAFYAAABXAAAAWAAAAFkAAABaAAAAWwAAAFwAAABdAAAAXgAAAF8AAABgAAAAYQAAAGIAAABjAAAAZAAAAGUAAABmAAAAZwAAAGgAAABpAAAAagAAAGsAAABsAAAAbQAAAG4AAABvAAAAcAAAAHEAAAByAAAAcwAAAHQAAAB1AAAAdgAAAHcAAAAAAAAABQAAAAoAAAAPAAAAFAAAABkAAAAeAAAAIwAAACgAAAAtAAAAMgAAADgAAAA+AAAARAAAAEoAAABQAAAAVgAAAFwAAABiAAAAaAAAAG4AAAB0AAAAegAAAIAAAACGAAAAjAAAAJIAAACYAAAAngAAAKQAAACqAAAAsAAAALYAAAC8AAAAwgAAAMgAAADOAAAA1AAAANoAAADgAAAA5gAAAOwAAADyAAAA+AAAAP4AAAAEAQAACgEAABABAAAWAQAAHAEAACIBAAAoAQAALgEAADQBAAA6AQAAQAEAAEYBAABMAQAAUgEAAFgBAABeAQAAZAEAAGoBAABwAQAAdgEAAHwBAACCAQAAiAEAAI4BAACUAQAAmgEAAKABAACmAQAArAEAALIBAAC4AQAAvgEAAMQBAADKAQAA0AEAANYBAADcAQAA4gEAAOgBAADuAQAA9AEAAPoBAAAAAgAABgIAAAwCAAASAgAAGAIAAB4CAAAkAgAAKgIAADACAAA2AgAAPAIAAEICAABIAgAATgIAAFUCAABcAgAAYwIAAGoCAABxAgAAeAIAAH8CAACGAgAAjQIAAJQCAACbAgAAogIAAKkCAACwAgAAtwIAAL4CAADFAgAAzAIAANMCAADaAgAAAAAAAHJvdy0wcm93LTFyb3ctMnJvdy0zcm93LTRyb3ctNXJvdy02cm93LTdyb3ctOHJvdy05cm93LTEwcm93LTExcm93LTEycm93LTEzcm93LTE0cm93LTE1cm93LTE2cm93LTE3cm93LTE4cm93LTE5cm93LTIwcm93LTIxcm93LTIycm93LTIzcm93LTI0cm93LTI1cm93LTI2cm93LTI3cm93LTI4cm93LTI5cm93LTMwcm93LTMxcm93LTMycm93LTMzcm93LTM0cm93LTM1cm93LTM2cm93LTM3cm93LTM4cm93LTM5cm93LTQwcm93LTQxcm93LTQycm93LTQzcm93LTQ0cm93LTQ1cm93LTQ2cm93LTQ3cm93LTQ4cm93LTQ5cm93LTUwcm93LTUxcm93LTUycm93LTUzcm93LTU0cm93LTU1cm93LTU2cm93LTU3cm93LTU4cm93LTU5cm93LTYwcm93LTYxcm93LTYycm93LTYzcm93LTY0cm93LTY1cm93LTY2cm93LTY3cm93LTY4cm93LTY5cm93LTcwcm93LTcxcm93LTcycm93LTczcm93LTc0cm93LTc1cm93LTc2cm93LTc3cm93LTc4cm93LTc5cm93LTgwcm93LTgxcm93LTgycm93LTgzcm93LTg0cm93LTg1cm93LTg2cm93LTg3cm93LTg4cm93LTg5cm93LTkwcm93LTkxcm93LTkycm93LTkzcm93LTk0cm93LTk1cm93LTk2cm93LTk3cm93LTk4cm93LTk5cm93LTEwMHJvdy0xMDFyb3ctMTAycm93LTEwM3Jvdy0xMDRyb3ctMTA1cm93LTEwNnJvdy0xMDdyb3ctMTA4cm93LTEwOXJvdy0xMTByb3ctMTExcm93LTExMnJvdy0xMTNyb3ctMTE0cm93LTExNXJvdy0xMTZyb3ctMTE3cm93LTExOHJvdy0xMTkAAAAAAAD/////AAAAABAAAAAMABQABgAIAAwAEAAMAAAAAAAEADQAAAAkAAAABAAAAAEAAAC4AAAAAAAAANAAAAAAAAAAqAYAAAAAAAAAAAAACAAIAAAABAAIAAAABAAAAAIAAABEAAAABAAAANT///8AAAEFEAAAABwAAAAEAAAAAAAAAAQAAABuYW1lAAAAAAQABAAEAAAAEAAUAAgABgAHAAwAAAAQABAAAAAAAAECEAAAABwAAAAEAAAAAAAAAAIAAABpZAAACAAMAAgABwAIAAAAAAAAASAAAADQAAAAQVJST1cx")!))
        XCTAssertEqual(largeArrow.table?.rows.count, 100)
        XCTAssertEqual(largeArrow.table?.omittedRowCount, 20)
        XCTAssertTrue(largeArrow.truncated)
        let largeAvro = try PreviewLoader.load(write("Large.avro", Data(base64Encoded: "T2JqAQQUYXZyby5jb2RlYw5kZWZsYXRlFmF2cm8uc2NoZW1h4AF7InR5cGUiOiAicmVjb3JkIiwgIm5hbWUiOiAiUm93IiwgImZpZWxkcyI6IFt7Im5hbWUiOiAiaWQiLCAidHlwZSI6ICJpbnQifSwgeyJuYW1lIjogIm5hbWUiLCAidHlwZSI6ICJzdHJpbmcifV19AOgOpyeNu4qFO3sVq9vTzRXwAYoGNdLdZxBgHMXxlpnMzEySSTIzmcrz/pJMZjLJTJIkk8xkZstkm0mSJJkkM5NkkszMTJIkmZnJJMnMTJKZmcn+hnjO+V19vjfn7hyoHhocOa0OFnRlwVQV7KGCqy74mkKoLcS6Qqov5MM1Za6OQH0UmgZoj0F3HPoTMDTC2ARTM8wni0a1QH0KmjPQKugM9A6GAGOC6SzM54pWtUJ9Hpo2aNuhuwB9BwwXYbwEUyfMXUWnLkN9BZqr0F6D7jr0N2DohvEmTLdg7il61Qv1bWj6oO2HbgD6OzAMwXgXpmGYR4tBjUF9D5r70D6oQLiHDP+IER4z4hNGesrI44ionjH0c4Z5wbATDDfJ8FOM8JIRXzHSa0aeRiT1hqHfMsw7hp1huFmGn2OEeUZcYKT3jPwBkdVHhv7EMJ8Z9gvDfWX4RUZYYsRlRlph5G8VtTi9WpXS36XMDyn7U8r9kvJrUmFdKm5IpU2p/Jul1R8p/VfKbEnZbSm3I+V3pcKeVPwnlfal8n+OUCboDqcnjbuKhTt7Favb080V")!))
        XCTAssertEqual(largeAvro.table?.rows.count, 100)
        XCTAssertEqual(largeAvro.table?.omittedRowCount, 20)
        XCTAssertTrue(largeAvro.truncated)
        let nested = try PreviewLoader.load(write("Nested.arrow", Data(base64Encoded: "QVJST1cxAAD/////2AAAABAAAAAAAAoADAAGAAUACAAKAAAAAAEEAAwAAAAIAAgAAAAEAAgAAAAEAAAAAgAAAHAAAAAEAAAAqP///wAAAQwUAAAAHAAAAAQAAAABAAAAFAAAAAQAAAB0YWdzAAAAANj////U////AAABBRAAAAAcAAAABAAAAAAAAAAEAAAAaXRlbQAAAAAEAAQABAAAABAAFAAIAAYABwAMAAAAEAAQAAAAAAABAhAAAAAcAAAABAAAAAAAAAACAAAAaWQAAAgADAAIAAcACAAAAAAAAAFAAAAAAAAAAP/////4AAAAFAAAAAAAAAAMABYABgAFAAgADAAMAAAAAAMEABgAAAA4AAAAAAAAAAAACgAYAAwABAAIAAoAAACMAAAAEAAAAAIAAAAAAAAAAAAAAAcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAwAAAAAAAAAIAAAAAAAAAAAAAAAAAAAACAAAAAAAAAAEAAAAAAAAAAwAAAAAAAAAAMAAAAAAAAAAAAAAAMAAAACAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAMAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAIAAAAAAAAAAAAAAAIAAAADAAAAAAAAAAAAAAABAAAAAgAAAAMAAABhYmMAAAAAAP////8AAAAAEAAAAAwAFAAGAAgADAAQAAwAAAAAAAQAOAAAACgAAAAEAAAAAQAAAOgAAAAAAAAAAAEAAAAAAAA4AAAAAAAAAAAAAAAAAAAACAAIAAAABAAIAAAABAAAAAIAAABwAAAABAAAAKj///8AAAEMFAAAABwAAAAEAAAAAQAAABQAAAAEAAAAdGFncwAAAADY////1P///wAAAQUQAAAAHAAAAAQAAAAAAAAABAAAAGl0ZW0AAAAABAAEAAQAAAAQABQACAAGAAcADAAAABAAEAAAAAAAAQIQAAAAHAAAAAQAAAAAAAAAAgAAAGlkAAAIAAwACAAHAAgAAAAAAAABQAAAAAABAABBUlJPVzE=")!))
        XCTAssertEqual(nested.table?.columns, ["字段", "类型", "可空"])
        XCTAssertEqual(nested.table?.rows.count, 2)
        XCTAssertEqual(nested.table?.rows[1][0], "tags")
        XCTAssertTrue(nested.summary.contains("schema"))
        XCTAssertTrue(nested.truncated)
    }
    func testDamagedAndUnsupportedColumnarDataAreExplicit() throws {
        for name in ["Broken.parquet", "Broken.arrow", "Broken.avro"] {
            XCTAssertThrowsError(try PreviewLoader.load(write(name, Data("broken".utf8)))) { error in
                XCTAssertTrue(error.localizedDescription.contains("数据文件已损坏"), name)
            }
        }
        var featherV1 = Data("FEA1".utf8); featherV1.append(Data(repeating: 0, count: 20))
        XCTAssertThrowsError(try PreviewLoader.load(write("Old.feather", featherV1))) { error in
            XCTAssertTrue(error.localizedDescription.contains("Feather v1"))
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
    func testOfficialCodeAndConfigCoverage() throws {
        let names = [
            "sample.asm", "sample.awk", "sample.bat", "build.bazel", "workspace.bazel", "build", "sample.bzl",
            "CMakeLists.txt", "sample.cmake", "sample.cmd", "sample.coffee", "sample.cr", "sample.d", "sample.diff",
            "Dockerfile", "sample.env", "sample.f", "sample.f03", "sample.f08", "sample.f90", "sample.f95",
            "sample.for", "sample.gd", "sample.gql", "sample.gradle", "sample.graphql", "sample.groovy",
            "sample.hcl", "sample.hs", "sample.ini", "sample.jl", "sample.lhs", "LICENSE", "sample.litcoffee",
            "sample.log", "Makefile", "sample.ml", "sample.mli", "sample.nim", "sample.nu", "sample.patch",
            "sample.proto", "sample.py", "sample.raku", "sample.rakumod", "sample.rakutest", "README", "sample.rkt",
            "sample.s", "sample.scm", "sample.sol", "sample.sql", "sample.ss", "sample.star", "sample.sv",
            "sample.svh", "sample.swift", "sample.tcl", "sample.tf", "sample.tfvars", "sample.toml", "sample.ts",
            "sample.v", "sample.vh", "workspace", "sample.xml", "sample.xsd", "sample.xsl", "sample.xslt",
            "sample.yaml", "sample.yml", "sample.zig"
        ]
        XCTAssertEqual(names.count, 72)
        var languages: [String: String] = [:]
        for name in names {
            let snapshot = try PreviewLoader.load(write(name, Data("value = 42\n".utf8)))
            XCTAssertEqual(snapshot.contentKind, .code, name)
            languages[name] = snapshot.language
        }
        XCTAssertEqual(languages["CMakeLists.txt"], "CMake")
        XCTAssertEqual(languages["build"], "Bazel")
        XCTAssertEqual(languages["sample.f90"], "Fortran")
        XCTAssertEqual(languages["sample.proto"], "Protocol Buffers")
        XCTAssertEqual(languages["sample.sv"], "SystemVerilog")
        XCTAssertEqual(languages["sample.tfvars"], "Terraform")
        XCTAssertEqual(languages["sample.zig"], "Zig")
    }

    func testHostAppIsPreviewOnlyAndCustomKindsAreNeutral() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appData = try Data(contentsOf: root.appendingPathComponent("Config/App-Info.plist"))
        let appInfo = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: appData, format: nil) as? [String: Any]
        )

        XCTAssertNil(appInfo["CFBundleDocumentTypes"], "The host app must never register as a document opener")

        let exported = try XCTUnwrap(appInfo["UTExportedTypeDeclarations"] as? [[String: Any]])
        XCTAssertEqual(exported.compactMap { $0["UTTypeIdentifier"] as? String }, ["io.github.linzh0632.spacelens.sample"])

        let imported = try XCTUnwrap(appInfo["UTImportedTypeDeclarations"] as? [[String: Any]])
        XCTAssertFalse(imported.isEmpty)
        for declaration in imported {
            let description = try XCTUnwrap(declaration["UTTypeDescription"] as? String)
            XCTAssertFalse(description.localizedCaseInsensitiveContains("SpaceLens"), description)
        }

        let previewData = try Data(contentsOf: root.appendingPathComponent("Config/Preview-Info.plist"))
        let previewInfo = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: previewData, format: nil) as? [String: Any]
        )
        let extensionInfo = try XCTUnwrap(previewInfo["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        let supported = Set(try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String]))
        let declared = Set((exported + imported).compactMap { $0["UTTypeIdentifier"] as? String })
        XCTAssertTrue(declared.isSubset(of: supported), "Every custom type must remain available to Quick Look")
    }

}

private struct ZipEntry {
    let name: String
    let compressed: UInt32
    let uncompressed: UInt32
    var flags: UInt16 = 0
}

private struct TarEntry {
    let name: String
    var payload = Data()
    var folder = false
}

private extension PreviewLoaderTests {
    func makeSQLite(_ name: String, statements: [String]) throws -> URL {
        let url = directory.appendingPathComponent(name)
        var database: OpaquePointer?
        let status = url.path.withCString {
            test_sqlite3_open_v2($0, &database, 0x0000_0002 | 0x0000_0004, nil)
        }
        guard status == 0, let database else { throw NSError(domain: "SQLiteFixture", code: Int(status)) }
        defer { _ = test_sqlite3_close_v2(database) }
        for sql in statements {
            var statement: OpaquePointer?
            let prepared = sql.withCString { test_sqlite3_prepare_v2(database, $0, -1, &statement, nil) }
            guard prepared == 0, let statement else { throw NSError(domain: "SQLiteFixture", code: Int(prepared)) }
            defer { _ = test_sqlite3_finalize(statement) }
            let stepped = test_sqlite3_step(statement)
            guard stepped == 101 else { throw NSError(domain: "SQLiteFixture", code: Int(stepped)) }
        }
        return url
    }

    func makeTar(_ entries: [TarEntry]) -> Data {
        var archive = Data()
        for entry in entries {
            var header = Data(repeating: 0, count: 512)
            header.writeASCII(entry.name, at: 0, length: 100)
            header.writeOctal(entry.folder ? 0o755 : 0o644, at: 100, length: 8)
            header.writeOctal(0, at: 108, length: 8)
            header.writeOctal(0, at: 116, length: 8)
            header.writeOctal(UInt64(entry.payload.count), at: 124, length: 12)
            header.writeOctal(1_700_000_000, at: 136, length: 12)
            header.replaceSubrange(148..<156, with: Data(repeating: 0x20, count: 8))
            header[156] = entry.folder ? 0x35 : 0x30
            header.writeASCII("ustar\0", at: 257, length: 6)
            header.writeASCII("00", at: 263, length: 2)
            let checksum = header.reduce(0) { $0 + UInt64($1) }
            let field = String(format: "%06llo\0 ", checksum)
            header.writeASCII(field, at: 148, length: 8)
            archive.append(header)
            archive.append(entry.payload)
            let padding = (512 - entry.payload.count % 512) % 512
            archive.append(Data(repeating: 0, count: padding))
        }
        archive.append(Data(repeating: 0, count: 1_024))
        return archive
    }

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

@_silgen_name("sqlite3_open_v2") private func test_sqlite3_open_v2(_ filename: UnsafePointer<CChar>?, _ database: UnsafeMutablePointer<OpaquePointer?>?, _ flags: Int32, _ vfs: UnsafePointer<CChar>?) -> Int32
@_silgen_name("sqlite3_close_v2") private func test_sqlite3_close_v2(_ database: OpaquePointer?) -> Int32
@_silgen_name("sqlite3_prepare_v2") private func test_sqlite3_prepare_v2(_ database: OpaquePointer?, _ sql: UnsafePointer<CChar>?, _ bytes: Int32, _ statement: UnsafeMutablePointer<OpaquePointer?>?, _ tail: UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32
@_silgen_name("sqlite3_step") private func test_sqlite3_step(_ statement: OpaquePointer?) -> Int32
@_silgen_name("sqlite3_finalize") private func test_sqlite3_finalize(_ statement: OpaquePointer?) -> Int32

private extension Data {
    mutating func writeASCII(_ value: String, at offset: Int, length: Int) {
        let bytes = Data(value.utf8.prefix(length))
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }
    mutating func writeOctal(_ value: UInt64, at offset: Int, length: Int) {
        let text = String(format: "%0*llo", length - 1, value) + "\0"
        writeASCII(text, at: offset, length: length)
    }
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
