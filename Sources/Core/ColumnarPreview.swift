import Foundation
import Compression

enum ColumnarPreview {
    static let extensions: Set<String> = ["parquet", "arrow", "feather", "avro"]
    private static let maximumFileBytes = 64 * 1024 * 1024
    private static let maximumRows = 100
    private static let maximumColumns = 100

    static func load(_ url: URL) throws -> PreviewSnapshot {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumFileBytes else {
            throw PreviewFailure.unsupportedData("文件超过 64 MiB 的安全读取上限。")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumFileBytes else { throw PreviewFailure.unsupportedData("文件超过 64 MiB 的安全读取上限。") }
        try Task.checkCancellation()
        switch url.pathExtension.lowercased() {
        case "parquet": return try loadParquet(url, data)
        case "arrow", "feather": return try loadArrow(url, data)
        case "avro": return try loadAvro(url, data)
        default: throw PreviewFailure.unsupported
        }
    }

    // MARK: Parquet metadata (Thrift Compact Protocol)

    private static func loadParquet(_ url: URL, _ data: Data) throws -> PreviewSnapshot {
        guard data.count >= 12, data.prefix(4) == Data("PAR1".utf8), data.suffix(4) == Data("PAR1".utf8) else {
            throw PreviewFailure.damagedData("Parquet 文件头或文件尾标记无效。")
        }
        let footerLength = Int(try data.readUInt32LE(at: data.count - 8))
        guard footerLength > 0, footerLength <= data.count - 12 else {
            throw PreviewFailure.damagedData("Parquet 元数据长度超出文件范围。")
        }
        let footerStart = data.count - 8 - footerLength
        var cursor = CompactCursor(Data(data[footerStart..<(data.count - 8)]))
        var budget = 50_000
        let metadata = try cursor.readStruct(depth: 0, budget: &budget)
        let totalRows = metadata[3]?.intValue ?? 0
        guard totalRows >= 0 else { throw PreviewFailure.damagedData("Parquet 行数为负数。") }
        let rowGroups = metadata[4]?.listValue?.count ?? 0
        let createdBy = metadata[6]?.stringValue
        let keyValues = parseKeyValues(metadata[5])
        let schemaElements = metadata[2]?.listValue?.compactMap(\.structValue) ?? []
        guard !schemaElements.isEmpty else { throw PreviewFailure.damagedData("Parquet schema 缺失。") }
        let fields = parquetFields(schemaElements)
        let visible = Array(fields.prefix(maximumColumns))
        let rows = visible.map { [$0.path, $0.physical, $0.logical, $0.repetition] }
        let omitted = max(0, fields.count - visible.count)
        var body = "行数：\(totalRows)\n行组：\(rowGroups)\n字段：\(fields.count)"
        if let createdBy, !createdBy.isEmpty { body += "\n创建器：\(createdBy)" }
        if !keyValues.isEmpty {
            body += "\n\n文件元信息：\n" + keyValues.prefix(50).map { "\($0.0)：\($0.1)" }.joined(separator: "\n")
        }
        let limit = omitted > 0 ? " · 仅显示前 \(maximumColumns) 列" : ""
        return PreviewSnapshot(title: url.lastPathComponent,
            summary: "SpaceLens · Parquet · \(totalRows) 行 · \(fields.count) 列 · \(rowGroups) 个行组 · schema/元信息\(limit)",
            body: body, truncated: omitted > 0, contentKind: .table,
            table: .init(columns: ["字段", "物理类型", "逻辑类型", "重复规则"], rows: rows, omittedRowCount: omitted))
    }

    private struct ParquetField { let path: String; let physical: String; let logical: String; let repetition: String }

    private static func parquetFields(_ elements: [[Int: CompactValue]]) -> [ParquetField] {
        struct Parent { var remaining: Int; let path: String }
        var parents: [Parent] = []
        var result: [ParquetField] = []
        for (index, element) in elements.enumerated() {
            while let last = parents.last, last.remaining == 0 { parents.removeLast() }
            if !parents.isEmpty { parents[parents.count - 1].remaining -= 1 }
            let name = element[4]?.stringValue ?? "字段 \(index)"
            let path = index == 0 ? "" : ([parents.last?.path, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "."))
            let children = Int(element[5]?.intValue ?? 0)
            if children > 0 { parents.append(Parent(remaining: children, path: path)) }
            guard index > 0, let type = element[1]?.intValue else { continue }
            let physical = parquetPhysical(Int(type), length: element[2]?.intValue)
            let logical = parquetLogical(Int(element[6]?.intValue ?? -1))
            let repetition = [0: "必填", 1: "可空", 2: "重复"][Int(element[3]?.intValue ?? 1)] ?? "未知"
            result.append(.init(path: path, physical: physical, logical: logical, repetition: repetition))
        }
        return result
    }

    private static func parquetPhysical(_ type: Int, length: Int64?) -> String {
        let names = [0: "BOOLEAN", 1: "INT32", 2: "INT64", 3: "INT96", 4: "FLOAT", 5: "DOUBLE", 6: "BYTE_ARRAY", 7: "FIXED_LEN_BYTE_ARRAY"]
        let base = names[type] ?? "UNKNOWN(\(type))"
        return type == 7 && length != nil ? "\(base)(\(length!))" : base
    }

    private static func parquetLogical(_ type: Int) -> String {
        let names = [0:"UTF8",1:"MAP",2:"MAP_KEY_VALUE",3:"LIST",4:"ENUM",5:"DECIMAL",6:"DATE",7:"TIME_MILLIS",8:"TIME_MICROS",9:"TIMESTAMP_MILLIS",10:"TIMESTAMP_MICROS",11:"UINT_8",12:"UINT_16",13:"UINT_32",14:"UINT_64",15:"INT_8",16:"INT_16",17:"INT_32",18:"INT_64",19:"JSON",20:"BSON",21:"INTERVAL"]
        return names[type] ?? "—"
    }

    private static func parseKeyValues(_ value: CompactValue?) -> [(String, String)] {
        value?.listValue?.compactMap { item in
            guard let fields = item.structValue, let key = fields[1]?.stringValue else { return nil }
            return (key, fields[2]?.stringValue ?? "")
        } ?? []
    }

    // MARK: Arrow IPC / Feather v2

    private static func loadArrow(_ url: URL, _ data: Data) throws -> PreviewSnapshot {
        guard data.count >= 16 else { throw PreviewFailure.damagedData("Arrow IPC 文件过短。") }
        if data.prefix(4) == Data("FEA1".utf8) {
            throw PreviewFailure.unsupportedData("Feather v1 暂不支持；请转换为 Feather v2（Arrow IPC）。")
        }
        let magic = Data("ARROW1".utf8)
        guard data.prefix(6) == magic, data.suffix(6) == magic else {
            throw PreviewFailure.damagedData("Arrow IPC/Feather v2 文件标记无效。")
        }
        let footerLength = Int(try data.readUInt32LE(at: data.count - 10))
        guard footerLength > 0, footerLength <= data.count - 16 else {
            throw PreviewFailure.damagedData("Arrow footer 长度超出文件范围。")
        }
        let footerStart = data.count - 10 - footerLength
        let footerData = Data(data[footerStart..<(data.count - 10)])
        let footer = try FBTable.root(in: footerData)
        guard let schema = try footer.indirectTable(field: 1) else { throw PreviewFailure.damagedData("Arrow schema 缺失。") }
        let fields = try parseArrowFields(schema)
        guard !fields.isEmpty else { throw PreviewFailure.damagedData("Arrow schema 没有字段。") }
        let blocks = try footer.structVector(field: 3, stride: 24)
        let canDecodeRows = fields.allSatisfy(\.rowDecodable)
        var rows: [[String]] = []
        var totalRows: Int64 = 0
        var unsupportedRows = false
        for block in blocks {
            try Task.checkCancellation()
            let offset = try footerData.readInt64LE(at: block)
            let metadataLength = Int(try footerData.readInt32LE(at: block + 8))
            guard offset >= 0, metadataLength > 0, offset <= Int64(data.count), Int(offset) + metadataLength <= data.count else {
                throw PreviewFailure.damagedData("Arrow record batch 的偏移超出文件范围。")
            }
            let batch = try parseArrowBatch(data: data, offset: Int(offset), metadataLength: metadataLength,
                                            fields: fields, rowBudget: max(0, maximumRows - rows.count),
                                            decodeRows: canDecodeRows)
            let (sum, overflow) = totalRows.addingReportingOverflow(batch.totalRows)
            guard !overflow else { throw PreviewFailure.damagedData("Arrow 总行数溢出。") }
            totalRows = sum
            rows.append(contentsOf: batch.rows)
            unsupportedRows = unsupportedRows || batch.unsupported
        }
        let schemaBody = fields.map { "\($0.name)：\($0.typeName)\($0.nullable ? "?" : "")" }.joined(separator: "\n")
        let format = url.pathExtension.lowercased() == "feather" ? "Feather v2" : "Arrow IPC"
        let limits = fields.count > maximumColumns ? " · 仅显示前 \(maximumColumns) 列" : ""
        if !canDecodeRows || unsupportedRows {
            let schemaRows = fields.prefix(maximumColumns).map { [$0.name, $0.typeName, $0.nullable ? "是" : "否"] }
            return PreviewSnapshot(title: url.lastPathComponent,
                summary: "SpaceLens · \(format) · \(totalRows) 行 · \(fields.count) 列 · \(blocks.count) 个批次 · 复杂/压缩列显示 schema\(limits)",
                body: schemaBody, truncated: true, contentKind: .table,
                table: .init(columns: ["字段", "类型", "可空"], rows: schemaRows,
                             omittedRowCount: max(0, fields.count - schemaRows.count)))
        }
        let columns = fields.prefix(maximumColumns).map(\.name)
        let clippedRows = rows.map { Array($0.prefix(columns.count)) }
        let omitted = max(0, Int(clamping: totalRows) - clippedRows.count)
        return PreviewSnapshot(title: url.lastPathComponent,
            summary: "SpaceLens · \(format) · \(totalRows) 行 · \(fields.count) 列 · \(blocks.count) 个批次\(limits)",
            body: schemaBody, truncated: omitted > 0 || fields.count > maximumColumns,
            contentKind: .table,
            table: .init(columns: Array(columns), rows: clippedRows, omittedRowCount: omitted))
    }

    private enum ArrowKind {
        case signed(Int), unsigned(Int), float32, float64, bool, utf8, binary
        case date32, date64, time(Int), timestamp(Int), fixedBinary(Int), complex
    }
    private struct ArrowFieldInfo {
        let name: String; let typeName: String; let nullable: Bool; let kind: ArrowKind
        let children: [ArrowFieldInfo]; let dictionaryEncoded: Bool
        var rowDecodable: Bool {
            guard !dictionaryEncoded else { return false }
            switch kind { case .complex: return false; default: return children.allSatisfy(\.rowDecodable) }
        }
    }
    private struct ArrowBatch { let totalRows: Int64; let rows: [[String]]; let unsupported: Bool }
    private struct ArrowNode { let length: Int64; let nullCount: Int64 }
    private struct ArrowBufferInfo { let offset: Int64; let length: Int64 }

    private static func parseArrowFields(_ schema: FBTable) throws -> [ArrowFieldInfo] {
        let tables = try schema.tableVector(field: 1)
        guard tables.count <= 1_000 else { throw PreviewFailure.damagedData("Arrow 字段数量异常。") }
        return try tables.map(parseArrowField)
    }

    private static func parseArrowField(_ table: FBTable) throws -> ArrowFieldInfo {
        let name = try table.string(field: 0) ?? "未命名字段"
        let nullable = try table.bool(field: 1, default: false)
        let typeID = Int(try table.uint8(field: 2, default: 0))
        let typeTable = try table.indirectTable(field: 3)
        let children = try table.tableVector(field: 5).map(parseArrowField)
        let pair: (String, ArrowKind)
        switch typeID {
        case 2:
            let bits = Int(try typeTable?.int32(field: 0, default: 32) ?? 32)
            let signed = try typeTable?.bool(field: 1, default: true) ?? true
            pair = ("\(signed ? "Int" : "UInt")\(bits)", signed ? .signed(bits) : .unsigned(bits))
        case 3:
            let precision = Int(try typeTable?.int16(field: 0, default: 1) ?? 1)
            pair = precision == 2 ? ("Float64", .float64) : ("Float32", .float32)
        case 4: pair = ("Binary", .binary)
        case 5: pair = ("String", .utf8)
        case 6: pair = ("Boolean", .bool)
        case 8:
            let unit = Int(try typeTable?.int16(field: 0, default: 0) ?? 0)
            pair = unit == 0 ? ("Date32", .date32) : ("Date64", .date64)
        case 9:
            let bits = Int(try typeTable?.int32(field: 1, default: 32) ?? 32)
            pair = ("Time\(bits)", .time(bits))
        case 10:
            let unit = Int(try typeTable?.int16(field: 0, default: 1) ?? 1)
            pair = ("Timestamp", .timestamp(unit))
        case 15:
            let width = Int(try typeTable?.int32(field: 0, default: 0) ?? 0)
            pair = ("FixedSizeBinary(\(width))", .fixedBinary(width))
        case 1: pair = ("Null", .complex)
        case 12: pair = ("List", .complex)
        case 13: pair = ("Struct", .complex)
        case 17: pair = ("Map", .complex)
        case 19: pair = ("LargeBinary", .complex)
        case 20: pair = ("LargeString", .complex)
        default: pair = ("ArrowType(\(typeID))", .complex)
        }
        return .init(name: name, typeName: pair.0, nullable: nullable, kind: pair.1, children: children,
                     dictionaryEncoded: try table.fieldPosition(4) != nil)
    }

    private static func parseArrowBatch(data: Data, offset: Int, metadataLength: Int,
                                        fields: [ArrowFieldInfo], rowBudget: Int,
                                        decodeRows: Bool) throws -> ArrowBatch {
        var prefix = Int(try data.readUInt32LE(at: offset))
        var messageStart = offset + 4
        if UInt32(prefix) == UInt32.max {
            prefix = Int(try data.readUInt32LE(at: messageStart)); messageStart += 4
        }
        guard prefix > 0, messageStart + prefix <= data.count, messageStart + prefix <= offset + metadataLength else {
            throw PreviewFailure.damagedData("Arrow batch metadata 长度无效。")
        }
        let message = try FBTable.root(in: Data(data[messageStart..<(messageStart + prefix)]))
        guard try message.uint8(field: 1, default: 0) == 3,
              let record = try message.indirectTable(field: 2) else {
            throw PreviewFailure.damagedData("Arrow batch 消息类型无效。")
        }
        if try record.fieldPosition(3) != nil {
            return ArrowBatch(totalRows: try record.int64(field: 0, default: 0), rows: [], unsupported: true)
        }
        let total = try record.int64(field: 0, default: 0)
        guard total >= 0, total <= 1_000_000_000 else { throw PreviewFailure.damagedData("Arrow 行数异常。") }
        guard decodeRows else { return ArrowBatch(totalRows: total, rows: [], unsupported: true) }
        let nodePositions = try record.structVector(field: 1, stride: 16)
        let bufferPositions = try record.structVector(field: 2, stride: 16)
        let nodes = try nodePositions.map { ArrowNode(length: try record.data.readInt64LE(at: $0), nullCount: try record.data.readInt64LE(at: $0 + 8)) }
        let buffers = try bufferPositions.map { ArrowBufferInfo(offset: try record.data.readInt64LE(at: $0), length: try record.data.readInt64LE(at: $0 + 8)) }
        let bodyStart = offset + metadataLength
        let visibleCount = min(rowBudget, Int(total))
        var nodeIndex = 0, bufferIndex = 0, unsupported = false
        var columns: [[String]] = []
        for field in fields {
            let decoded = try decodeArrowColumn(field, rowCount: visibleCount, nodes: nodes, buffers: buffers,
                                                nodeIndex: &nodeIndex, bufferIndex: &bufferIndex,
                                                bodyStart: bodyStart, data: data)
            columns.append(decoded.values); unsupported = unsupported || decoded.unsupported
        }
        let rows = (0..<visibleCount).map { row in columns.map { row < $0.count ? $0[row] : "" } }
        return .init(totalRows: total, rows: rows, unsupported: unsupported)
    }

    private static func decodeArrowColumn(_ field: ArrowFieldInfo, rowCount: Int, nodes: [ArrowNode], buffers: [ArrowBufferInfo],
                                          nodeIndex: inout Int, bufferIndex: inout Int, bodyStart: Int, data: Data) throws -> (values:[String], unsupported:Bool) {
        guard nodeIndex < nodes.count else { throw PreviewFailure.damagedData("Arrow field node 缺失。") }
        let node = nodes[nodeIndex]; nodeIndex += 1
        func nextBuffer() throws -> ArrowBufferInfo {
            guard bufferIndex < buffers.count else { throw PreviewFailure.damagedData("Arrow data buffer 缺失。") }
            defer { bufferIndex += 1 }; return buffers[bufferIndex]
        }
        let validity = try nextBuffer()
        func valid(_ index: Int) throws -> Bool {
            if validity.length == 0 { return true }
            let position = try checkedBuffer(validity, bodyStart: bodyStart, data: data)
            guard index / 8 < validity.length else { throw PreviewFailure.damagedData("Arrow validity bitmap 越界。") }
            return (data[position + index / 8] & UInt8(1 << (index % 8))) != 0
        }
        switch field.kind {
        case .utf8, .binary:
            let offsets = try nextBuffer(), values = try nextBuffer()
            let offsetsStart = try checkedBuffer(offsets, bodyStart: bodyStart, data: data)
            let valuesStart = try checkedBuffer(values, bodyStart: bodyStart, data: data)
            guard offsets.length >= Int64((min(Int(node.length), rowCount) + 1) * 4) else { throw PreviewFailure.damagedData("Arrow 字符串偏移表过短。") }
            var output:[String]=[]
            for index in 0..<rowCount {
                if try !valid(index) { output.append("NULL"); continue }
                let a=Int(try data.readInt32LE(at: offsetsStart+index*4)), b=Int(try data.readInt32LE(at: offsetsStart+(index+1)*4))
                guard a>=0,b>=a,Int64(b)<=values.length else { throw PreviewFailure.damagedData("Arrow 字符串偏移越界。") }
                let bytes=Data(data[(valuesStart+a)..<(valuesStart+b)])
                if case .utf8 = field.kind { output.append(String(data:bytes,encoding:.utf8) ?? "<无效 UTF-8>") }
                else { output.append(hexSummary(bytes)) }
            }
            return (output,false)
        case .bool:
            let values=try nextBuffer(), start=try checkedBuffer(values,bodyStart:bodyStart,data:data)
            guard values.length >= Int64((rowCount + 7) / 8) else { throw PreviewFailure.damagedData("Arrow Boolean buffer 过短。") }
            return (try (0..<rowCount).map { i in try valid(i) ? (((data[start+i/8] >> (i%8)) & 1)==1 ? "true":"false") : "NULL" },false)
        case .signed(let bits), .unsigned(let bits), .time(let bits):
            let values=try nextBuffer(), start=try checkedBuffer(values,bodyStart:bodyStart,data:data), width=max(1,bits/8)
            guard values.length >= Int64(rowCount*width) else { throw PreviewFailure.damagedData("Arrow 数值 buffer 过短。") }
            let signed:Bool; if case .unsigned = field.kind { signed=false } else { signed=true }
            return (try (0..<rowCount).map { i in
                if try !valid(i) { return "NULL" }
                return integerString(data,start+i*width,bits,signed)
            },false)
        case .float32:
            let values=try nextBuffer(), start=try checkedBuffer(values,bodyStart:bodyStart,data:data)
            guard values.length >= Int64(rowCount * 4) else { throw PreviewFailure.damagedData("Arrow Float32 buffer 过短。") }
            return (try (0..<rowCount).map { i in try valid(i) ? String(Float(bitPattern:try data.readUInt32LE(at:start+i*4))) : "NULL" },false)
        case .float64:
            let values=try nextBuffer(), start=try checkedBuffer(values,bodyStart:bodyStart,data:data)
            guard values.length >= Int64(rowCount * 8) else { throw PreviewFailure.damagedData("Arrow Float64 buffer 过短。") }
            return (try (0..<rowCount).map { i in try valid(i) ? String(Double(bitPattern:try data.readUInt64LE(at:start+i*8))) : "NULL" },false)
        case .date32:
            let values=try nextBuffer(), start=try checkedBuffer(values,bodyStart:bodyStart,data:data)
            guard values.length >= Int64(rowCount * 4) else { throw PreviewFailure.damagedData("Arrow Date32 buffer 过短。") }
            return (try (0..<rowCount).map { i in
                if try !valid(i) { return "NULL" }; let days=try data.readInt32LE(at:start+i*4)
                return ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:TimeInterval(days)*86400))
            },false)
        case .date64, .timestamp:
            let values=try nextBuffer(), start=try checkedBuffer(values,bodyStart:bodyStart,data:data)
            guard values.length >= Int64(rowCount * 8) else { throw PreviewFailure.damagedData("Arrow 64-bit buffer 过短。") }
            return (try (0..<rowCount).map { i in
                if try !valid(i) { return "NULL" }; return String(try data.readInt64LE(at:start+i*8))
            },false)
        case .fixedBinary(let width):
            let values=try nextBuffer(), start=try checkedBuffer(values,bodyStart:bodyStart,data:data)
            guard width>0,values.length>=Int64(rowCount*width) else { throw PreviewFailure.damagedData("Arrow fixed binary buffer 无效。") }
            return (try (0..<rowCount).map { i in try valid(i) ? hexSummary(Data(data[(start+i*width)..<(start+(i+1)*width)])) : "NULL" },false)
        case .complex:
            for child in field.children { _ = try decodeArrowColumn(child,rowCount:rowCount,nodes:nodes,buffers:buffers,nodeIndex:&nodeIndex,bufferIndex:&bufferIndex,bodyStart:bodyStart,data:data) }
            return (Array(repeating:"<\(field.typeName)>",count:rowCount),true)
        }
    }

    private static func checkedBuffer(_ buffer: ArrowBufferInfo, bodyStart: Int, data: Data) throws -> Int {
        guard buffer.offset>=0,buffer.length>=0,buffer.offset<=Int64(data.count),buffer.length<=Int64(data.count),
              Int64(bodyStart)+buffer.offset+buffer.length<=Int64(data.count) else { throw PreviewFailure.damagedData("Arrow buffer 越界。") }
        return bodyStart+Int(buffer.offset)
    }

    private static func integerString(_ data:Data,_ at:Int,_ bits:Int,_ signed:Bool)->String {
        if signed {
            switch bits { case 8:return String(Int8(bitPattern:data[at])); case 16:return String(Int16(bitPattern:(try? data.readUInt16LE(at:at)) ?? 0)); case 32:return String((try? data.readInt32LE(at:at)) ?? 0); default:return String((try? data.readInt64LE(at:at)) ?? 0) }
        } else {
            switch bits { case 8:return String(data[at]); case 16:return String((try? data.readUInt16LE(at:at)) ?? 0); case 32:return String((try? data.readUInt32LE(at:at)) ?? 0); default:return String((try? data.readUInt64LE(at:at)) ?? 0) }
        }
    }

    // MARK: Avro Object Container File

    private static func loadAvro(_ url: URL, _ data: Data) throws -> PreviewSnapshot {
        var cursor = BinaryCursor(data)
        guard try cursor.read(count:4) == Data([0x4f,0x62,0x6a,0x01]) else { throw PreviewFailure.damagedData("Avro OCF 文件标记无效。") }
        let metadata = try cursor.readAvroMapBytes(limit:100)
        guard let schemaData=metadata["avro.schema"], let schemaObject=try? JSONSerialization.jsonObject(with:schemaData,options:[.fragmentsAllowed]) else {
            throw PreviewFailure.damagedData("Avro schema 缺失或不是有效 JSON。")
        }
        let codec=metadata["avro.codec"].flatMap{String(data:$0,encoding:.utf8)} ?? "null"
        guard ["null","deflate"].contains(codec) else { throw PreviewFailure.unsupportedData("Avro codec \(codec) 暂不支持；当前支持 null 和 deflate。") }
        let sync=try cursor.read(count:16)
        let descriptor=try AvroSchemaDescriptor(schemaObject)
        var rows:[[String]]=[], total=0, truncated=false
        while !cursor.isAtEnd {
            try Task.checkCancellation()
            let count=try cursor.readLong()
            if count==0 { continue }
            guard count>0,count<=1_000_000_000 else { throw PreviewFailure.damagedData("Avro block 记录数异常。") }
            let size=try cursor.readLong(); guard size>=0,size<=Int64(maximumFileBytes) else { throw PreviewFailure.damagedData("Avro block 大小异常。") }
            let block=try cursor.read(count:Int(size)); guard try cursor.read(count:16)==sync else { throw PreviewFailure.damagedData("Avro block 同步标记不匹配。") }
            guard total <= Int.max - Int(count) else { throw PreviewFailure.damagedData("Avro 总行数溢出。") }
            total += Int(count)
            guard rows.count<maximumRows else { truncated=true; continue }
            let decoded = codec=="deflate" ? try inflateRaw(block, limit:maximumFileBytes) : block
            var blockCursor=BinaryCursor(decoded)
            for _ in 0..<min(Int(count),maximumRows-rows.count) {
                let value=try descriptor.decode(&blockCursor,depth:0)
                rows.append(descriptor.row(value))
            }
            if Int(count)>maximumRows-rows.count { truncated=true }
        }
        let omitted=max(0,total-rows.count)
        let keys=metadata.keys.sorted().filter{$0 != "avro.schema"}.map{"\($0)：\(String(data:metadata[$0]!,encoding:.utf8) ?? "<binary>")"}.joined(separator:"\n")
        let body="Schema：\n\(String(data:schemaData,encoding:.utf8) ?? "")" + (keys.isEmpty ? "":"\n\n元信息：\n\(keys)")
        return PreviewSnapshot(title:url.lastPathComponent,
            summary:"SpaceLens · Avro OCF · \(total) 行 · \(descriptor.columns.count) 列 · codec \(codec)",
            body:body,truncated:truncated || omitted>0,contentKind:.table,
            table:.init(columns:descriptor.columns,rows:rows,omittedRowCount:omitted))
    }

    private static func inflateRaw(_ data:Data,limit:Int)throws->Data {
        var capacity=max(64*1024,data.count*4)
        while capacity<=limit {
            var output=[UInt8](repeating:0,count:capacity)
            let size=data.withUnsafeBytes{ src in
                guard let base=src.bindMemory(to:UInt8.self).baseAddress else{return 0}
                return compression_decode_buffer(&output,capacity,base,data.count,nil,COMPRESSION_ZLIB)
            }
            if size>0 && size<capacity{return Data(output.prefix(size))}
            capacity*=2
        }
        throw PreviewFailure.damagedData("Avro deflate 数据损坏或解压后超过 64 MiB。")
    }

    private static func hexSummary(_ data:Data)->String { data.prefix(16).map{String(format:"%02X",$0)}.joined() + (data.count>16 ? "…":"") }
}

// MARK: Safe binary helpers

private extension Data {
    func checked(_ at:Int,_ count:Int)throws {
        guard at>=0,count>=0,at<=self.count-count else { throw PreviewFailure.damagedData("二进制字段超出文件范围。") }
    }
    func readUInt16LE(at:Int)throws->UInt16 { try checked(at,2); return UInt16(self[at]) | UInt16(self[at+1])<<8 }
    func readUInt32LE(at:Int)throws->UInt32 { try checked(at,4); return UInt32(self[at]) | UInt32(self[at+1])<<8 | UInt32(self[at+2])<<16 | UInt32(self[at+3])<<24 }
    func readUInt64LE(at:Int)throws->UInt64 { try checked(at,8); var v:UInt64=0; for i in 0..<8 {v |= UInt64(self[at+i]) << UInt64(i*8)}; return v }
    func readInt16LE(at:Int)throws->Int16 { Int16(bitPattern:try readUInt16LE(at:at)) }
    func readInt32LE(at:Int)throws->Int32 { Int32(bitPattern:try readUInt32LE(at:at)) }
    func readInt64LE(at:Int)throws->Int64 { Int64(bitPattern:try readUInt64LE(at:at)) }
}

private struct BinaryCursor {
    let data:Data; var index=0
    init(_ data:Data){self.data=data}
    var isAtEnd:Bool{index==data.count}
    mutating func readByte()throws->UInt8 { try data.checked(index,1); defer{index+=1}; return data[index] }
    mutating func read(count:Int)throws->Data { try data.checked(index,count); defer{index+=count}; return Data(data[index..<index+count]) }
    mutating func readLong()throws->Int64 {
        var raw:UInt64=0,shift:UInt64=0
        for _ in 0..<10 { let byte=try readByte(); raw |= UInt64(byte&0x7f)<<shift; if byte&0x80==0{return Int64(raw>>1) ^ -Int64(raw&1)}; shift+=7 }
        throw PreviewFailure.damagedData("Avro 可变整数过长。")
    }
    mutating func readBytes()throws->Data { let n=try readLong(); guard n>=0,n<=Int64(data.count-index) else{throw PreviewFailure.damagedData("Avro 字节串长度无效。")}; return try read(count:Int(n)) }
    mutating func readString()throws->String { let bytes=try readBytes(); guard let s=String(data:bytes,encoding:.utf8) else{throw PreviewFailure.damagedData("Avro 字符串不是 UTF-8。")}; return s }
    mutating func readAvroMapBytes(limit:Int)throws->[String:Data] {
        var result:[String:Data]=[:],count=try readLong(),seen=0
        while count != 0 {
            if count<0 {count = -count; _=try readLong()}
            guard count<=Int64(limit-seen) else{throw PreviewFailure.damagedData("Avro 元信息条目过多。")}
            for _ in 0..<count {result[try readString()]=try readBytes();seen+=1}
            count=try readLong()
        }
        return result
    }
}

private struct AvroSchemaDescriptor {
    let root:Any; let columns:[String]; let named:[String:Any]
    init(_ root:Any)throws {
        self.root=root; var names:[String:Any]=[:]; Self.collect(root,&names,depth:0); self.named=names
        if let d=root as? [String:Any],(d["type"] as? String)=="record",let fields=d["fields"] as? [[String:Any]] {columns=fields.compactMap{$0["name"] as? String}}
        else {columns=["值"]}
    }
    static func collect(_ schema:Any,_ names:inout[String:Any],depth:Int){guard depth<50 else{return}; if let d=schema as? [String:Any] {if let name=d["name"] as? String{names[name]=d}; if let fields=d["fields"] as? [[String:Any]]{for f in fields{if let t=f["type"]{collect(t,&names,depth:depth+1)}}}} else if let a=schema as? [Any]{for x in a{collect(x,&names,depth:depth+1)}}}
    func decode(_ c:inout BinaryCursor,depth:Int)throws->Any {
        guard depth<50 else{throw PreviewFailure.damagedData("Avro schema 嵌套过深。")}
        return try decodeSchema(root,&c,depth)
    }
    private func decodeSchema(_ schema:Any,_ c:inout BinaryCursor,_ depth:Int)throws->Any {
        if let union=schema as? [Any] {let i=try c.readLong();guard i>=0,i<Int64(union.count)else{throw PreviewFailure.damagedData("Avro union 索引无效。")};return try decodeSchema(union[Int(i)],&c,depth+1)}
        if let name=schema as? String {
            switch name {
            case "null":return NSNull(); case "boolean":return try c.readByte() != 0
            case "int","long":return try c.readLong()
            case "float":let b=try c.read(count:4);return Float(bitPattern:try b.readUInt32LE(at:0))
            case "double":let b=try c.read(count:8);return Double(bitPattern:try b.readUInt64LE(at:0))
            case "bytes":return try c.readBytes(); case "string":return try c.readString()
            default: if let target=named[name]{return try decodeSchema(target,&c,depth+1)}; throw PreviewFailure.unsupportedData("Avro 命名类型 \(name) 无法解析。")
            }
        }
        guard let d=schema as? [String:Any],let type=d["type"] else{throw PreviewFailure.damagedData("Avro schema 节点无效。")}
        if !(type is String){return try decodeSchema(type,&c,depth+1)}
        switch type as! String {
        case "record":
            guard let fields=d["fields"] as? [[String:Any]] else{throw PreviewFailure.damagedData("Avro record fields 缺失。")};var result:[String:Any]=[:]
            for f in fields {guard let name=f["name"] as? String,let child=f["type"] else{throw PreviewFailure.damagedData("Avro field 无效。")};result[name]=try decodeSchema(child,&c,depth+1)};return result
        case "enum":guard let symbols=d["symbols"] as? [String] else{throw PreviewFailure.damagedData("Avro enum 无效。")};let i=try c.readLong();guard i>=0,i<Int64(symbols.count)else{throw PreviewFailure.damagedData("Avro enum 索引无效。")};return symbols[Int(i)]
        case "fixed":guard let n=d["size"] as? Int,n>=0,n<=1_000_000 else{throw PreviewFailure.damagedData("Avro fixed 大小无效。")};return try c.read(count:n)
        case "array":guard let item=d["items"] else{throw PreviewFailure.damagedData("Avro array items 缺失。")};return try decodeArray(item,&c,depth)
        case "map":guard let value=d["values"] else{throw PreviewFailure.damagedData("Avro map values 缺失。")};return try decodeMap(value,&c,depth)
        default:return try decodeSchema(type,&c,depth+1)
        }
    }
    private func decodeArray(_ schema:Any,_ c:inout BinaryCursor,_ depth:Int)throws->[Any]{var out:[Any]=[],count=try c.readLong();while count != 0{if count<0{count = -count;_=try c.readLong()};guard count<=10_000-Int64(out.count)else{throw PreviewFailure.unsupportedData("Avro 数组超过 10,000 项限制。")};for _ in 0..<count{out.append(try decodeSchema(schema,&c,depth+1))};count=try c.readLong()};return out}
    private func decodeMap(_ schema:Any,_ c:inout BinaryCursor,_ depth:Int)throws->[String:Any]{var out:[String:Any]=[:],count=try c.readLong();while count != 0{if count<0{count = -count;_=try c.readLong()};guard count<=10_000-Int64(out.count)else{throw PreviewFailure.unsupportedData("Avro map 超过 10,000 项限制。")};for _ in 0..<count{out[try c.readString()]=try decodeSchema(schema,&c,depth+1)};count=try c.readLong()};return out}
    func row(_ value:Any)->[String]{if let d=value as? [String:Any]{return columns.map{Self.display(d[$0] ?? NSNull())}};return[Self.display(value)]}
    static func display(_ value:Any)->String{if value is NSNull{return"NULL"};if let d=value as? Data{return d.prefix(16).map{String(format:"%02X",$0)}.joined()+(d.count>16 ? "…":"")};if let a=value as? [Any]{return "["+a.prefix(20).map(display).joined(separator:", ")+(a.count>20 ? ", …]":"]")};if let d=value as? [String:Any]{return "{"+d.keys.sorted().prefix(20).map{"\($0): \(display(d[$0]!))"}.joined(separator:", ")+(d.count>20 ? ", …}":"}")};return String(describing:value)}
}

private enum CompactValue {
    case bool(Bool),int(Int64),double(Double),binary(Data),list([CompactValue]),map([(CompactValue,CompactValue)]),structure([Int:CompactValue])
    var intValue:Int64?{if case .int(let x)=self{return x};return nil}
    var stringValue:String?{if case .binary(let d)=self{return String(data:d,encoding:.utf8)};return nil}
    var listValue:[CompactValue]?{if case .list(let x)=self{return x};return nil}
    var structValue:[Int:CompactValue]?{if case .structure(let x)=self{return x};return nil}
}

private struct CompactCursor {
    let data:Data;var index=0
    init(_ data:Data){self.data=data}
    mutating func byte()throws->UInt8{try data.checked(index,1);defer{index+=1};return data[index]}
    mutating func varint()throws->UInt64{var x:UInt64=0,s:UInt64=0;for _ in 0..<10{let b=try byte();x|=UInt64(b&0x7f)<<s;if b&0x80==0{return x};s+=7};throw PreviewFailure.damagedData("Parquet Thrift varint 过长。")}
    mutating func zigzag()throws->Int64{let n=try varint();return Int64(n>>1) ^ -Int64(n&1)}
    mutating func readStruct(depth:Int,budget:inout Int)throws->[Int:CompactValue]{guard depth<64 else{throw PreviewFailure.damagedData("Parquet 元数据嵌套过深。")};var fields:[Int:CompactValue]=[:],last=0
        while true{let h=try byte();let type=Int(h&0x0f);if type==0{return fields};let delta=Int(h>>4);let id:Int;if delta==0{id=Int(try zigzag())}else{id=last+delta};last=id;fields[id]=try readValue(type,depth:depth+1,budget:&budget)} }
    mutating func readValue(_ type:Int,depth:Int,budget:inout Int)throws->CompactValue{budget-=1;guard budget>=0 else{throw PreviewFailure.damagedData("Parquet 元数据节点过多。")};switch type{case 1:return .bool(true);case 2:return .bool(false);case 3:return .int(Int64(Int8(bitPattern:try byte())));case 4,5,6:return .int(try zigzag());case 7:let d=try take(8);return .double(Double(bitPattern:try d.readUInt64LE(at:0)));case 8:let n=Int(try varint());guard n<=data.count-index else{throw PreviewFailure.damagedData("Parquet 二进制长度无效。")};return .binary(try take(n));case 9,10:let h=try byte();var n=Int(h>>4);let element=Int(h&0x0f);if n==15{n=Int(try varint())};guard n<=100_000 else{throw PreviewFailure.damagedData("Parquet list 过大。")};return .list(try(0..<n).map{_ in try readValue(element,depth:depth+1,budget:&budget)});case 11:let n=Int(try varint());if n==0{return .map([])};guard n<=100_000 else{throw PreviewFailure.damagedData("Parquet map 过大。")};let h=try byte(),k=Int(h>>4),v=Int(h&0x0f);return .map(try(0..<n).map{_ in(try readValue(k,depth:depth+1,budget:&budget),try readValue(v,depth:depth+1,budget:&budget))});case 12:return .structure(try readStruct(depth:depth+1,budget:&budget));default:throw PreviewFailure.damagedData("Parquet Thrift 类型 \(type) 无效。")}}
    mutating func take(_ n:Int)throws->Data{try data.checked(index,n);defer{index+=n};return Data(data[index..<index+n])}
}

private struct FBTable {
    let data:Data;let position:Int
    static func root(in data:Data)throws->FBTable{guard data.count>=4 else{throw PreviewFailure.damagedData("FlatBuffer 过短。")};let p=Int(try data.readUInt32LE(at:0));guard p>=4,p<data.count else{throw PreviewFailure.damagedData("FlatBuffer root 越界。")};return .init(data:data,position:p)}
    func fieldPosition(_ field:Int)throws->Int?{let back=Int(try data.readInt32LE(at:position));let vt=position-back;guard back != 0, vt >= 0, vt + 4 <= data.count else { throw PreviewFailure.damagedData("FlatBuffer vtable 无效。") };let length=Int(try data.readUInt16LE(at:vt));let entry=vt+4+field*2;if entry+2>vt+length{return nil};let offset=Int(try data.readUInt16LE(at:entry));if offset==0{return nil};let p=position+offset;try data.checked(p,1);return p}
    func indirectTable(field:Int)throws->FBTable?{guard let p=try fieldPosition(field)else{return nil};let target=p+Int(try data.readUInt32LE(at:p));guard target<data.count else{throw PreviewFailure.damagedData("FlatBuffer table 越界。")};return .init(data:data,position:target)}
    func uint8(field:Int,default d:UInt8)throws->UInt8{guard let p=try fieldPosition(field)else{return d};return data[p]}
    func bool(field:Int,default d:Bool)throws->Bool{try uint8(field:field,default:d ? 1:0) != 0}
    func int16(field:Int,default d:Int16)throws->Int16{guard let p=try fieldPosition(field)else{return d};return try data.readInt16LE(at:p)}
    func int32(field:Int,default d:Int32)throws->Int32{guard let p=try fieldPosition(field)else{return d};return try data.readInt32LE(at:p)}
    func int64(field:Int,default d:Int64)throws->Int64{guard let p=try fieldPosition(field)else{return d};return try data.readInt64LE(at:p)}
    func string(field:Int)throws->String?{guard let p=try fieldPosition(field)else{return nil};let start=p+Int(try data.readUInt32LE(at:p));let n=Int(try data.readUInt32LE(at:start));try data.checked(start+4,n);guard let s=String(data:data[(start+4)..<(start+4+n)],encoding:.utf8)else{throw PreviewFailure.damagedData("FlatBuffer 字符串不是 UTF-8。")};return s}
    func vector(field:Int,stride:Int)throws->[Int]{guard let p=try fieldPosition(field)else{return[]};let start=p+Int(try data.readUInt32LE(at:p));let n=Int(try data.readUInt32LE(at:start));guard n>=0,n<=100_000 else{throw PreviewFailure.damagedData("FlatBuffer vector 数量异常。")};try data.checked(start+4,n*stride);return(0..<n).map{start+4+$0*stride}}
    func structVector(field:Int,stride:Int)throws->[Int]{try vector(field:field,stride:stride)}
    func tableVector(field:Int)throws->[FBTable]{try vector(field:field,stride:4).map{p in let target=p+Int(try data.readUInt32LE(at:p));guard target<data.count else{throw PreviewFailure.damagedData("FlatBuffer vector table 越界。")};return FBTable(data:data,position:target)}}
}
