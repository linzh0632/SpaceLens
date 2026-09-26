import Foundation
import Compression

enum DiagramPreview {
    static let extensions: Set<String> = ["mermaid", "mmd", "puml", "plantuml", "drawio"]
    private static let maximumElements = 500

    static func load(source: String, truncated: Bool, name: String, ext: String,
                     byteLimit: Int) throws -> PreviewSnapshot {
        guard !truncated else {
            throw PreviewFailure.malformedText(L10n.text("图表超过 \(formatBytes(Int64(byteLimit))) 的安全读取上限。", "The diagram exceeds the \(formatBytes(Int64(byteLimit))) safe read limit."))
        }
        try Task.checkCancellation()
        let result: Rendered
        switch ext {
        case "mermaid", "mmd": result = try renderMermaid(source)
        case "puml", "plantuml": result = try renderPlantUML(source)
        case "drawio": result = try renderDrawIO(source)
        default: throw PreviewFailure.unsupported
        }
        return PreviewSnapshot(title: name,
            summary: L10n.text("SpaceLens · \(result.format) · \(L10n.count(result.elementCount, "个元素", "element", "elements")) · 本地安全渲染", "SpaceLens · \(result.format) · \(L10n.count(result.elementCount, "个元素", "element", "elements")) · rendered safely on this Mac"),
            body: source, truncated: result.truncated, contentKind: .diagram,
            language: result.format, diagramSVG: result.svg)
    }

    private static func renderMermaid(_ source: String) throws -> Rendered {
        let lines = meaningfulLines(source, commentPrefix: "%%")
        guard let first = lines.first else { throw malformed(L10n.text("Mermaid 文件为空。", "The Mermaid file is empty.")) }
        if first.lowercased().hasPrefix("sequencediagram") {
            return try renderSequence(Array(lines.dropFirst()), format: "Mermaid", plantUML: false)
        }
        guard first.lowercased().hasPrefix("flowchart") || first.lowercased().hasPrefix("graph") else {
            throw malformed(L10n.text("当前 Mermaid 预览支持 flowchart、graph 和 sequenceDiagram。", "The Mermaid preview supports flowchart, graph and sequenceDiagram."))
        }
        return try renderGraph(Array(lines.dropFirst()), format: "Mermaid")
    }

    private static func renderPlantUML(_ source: String) throws -> Rendered {
        var lines = meaningfulLines(source, commentPrefix: "'")
        lines.removeAll { $0.lowercased() == "@startuml" || $0.lowercased() == "@enduml" }
        guard !lines.isEmpty else { throw malformed(L10n.text("PlantUML 文件为空。", "The PlantUML file is empty.")) }
        let sequence = lines.contains { $0.contains("->") && $0.contains(":") }
        return sequence ? try renderSequence(lines, format: "PlantUML", plantUML: true)
                        : try renderGraph(lines, format: "PlantUML")
    }

    private static func renderGraph(_ lines: [String], format: String) throws -> Rendered {
        var nodes: [String: Node] = [:]
        var order: [String] = []
        var edges: [Edge] = []
        func add(_ token: String) {
            let parsed = parseNode(token)
            guard !parsed.id.isEmpty else { return }
            if nodes[parsed.id] == nil { order.append(parsed.id); nodes[parsed.id] = parsed }
            else if parsed.label != parsed.id { nodes[parsed.id] = parsed }
        }
        for line in lines.prefix(maximumElements) {
            try Task.checkCancellation()
            if let arrow = splitArrow(line) {
                add(arrow.left); add(arrow.right)
                let left = parseNode(arrow.left).id, right = parseNode(arrow.right).id
                if !left.isEmpty && !right.isEmpty { edges.append(.init(source: left, target: right, label: arrow.label)) }
            } else {
                let cleaned = line.replacingOccurrences(of: #"^(class|component|rectangle|node)\s+"#, with: "", options: .regularExpression)
                add(cleaned)
            }
        }
        guard !order.isEmpty else { throw malformed(L10n.text("没有识别到可渲染的节点。", "No renderable nodes were found.")) }
        let visibleOrder = Array(order.prefix(maximumElements))
        let width = 720.0
        let rowHeight = 110.0
        let height = max(180, 50 + Double(visibleOrder.count) * rowHeight)
        var positions: [String: (Double, Double)] = [:]
        for (index, id) in visibleOrder.enumerated() {
            let x = index.isMultiple(of: 2) ? 90.0 : 390.0
            let y = 35.0 + Double(index) * rowHeight
            positions[id] = (x, y)
        }
        var body = svgHeader(width: width, height: height)
        for edge in edges {
            guard let a = positions[edge.source], let b = positions[edge.target] else { continue }
            let x1 = a.0 + 120, y1 = a.1 + 56, x2 = b.0 + 120, y2 = b.1
            body += #"<path d="M \#(x1) \#(y1) C \#(x1) \#((y1+y2)/2), \#(x2) \#((y1+y2)/2), \#(x2) \#(y2)" class="edge" marker-end="url(#arrow)"/>"#
            if !edge.label.isEmpty { body += text(edge.label, x: (x1+x2)/2, y: (y1+y2)/2-6, css: "edgeLabel") }
        }
        for id in visibleOrder {
            guard let node = nodes[id], let p = positions[id] else { continue }
            switch node.shape {
            case .diamond:
                body += #"<polygon points="\#(p.0+120),\#(p.1) \#(p.0+240),\#(p.1+28) \#(p.0+120),\#(p.1+56) \#(p.0),\#(p.1+28)" class="node"/>"#
            case .round:
                body += #"<rect x="\#(p.0)" y="\#(p.1)" width="240" height="56" rx="28" class="node"/>"#
            default:
                body += #"<rect x="\#(p.0)" y="\#(p.1)" width="240" height="56" rx="10" class="node"/>"#
            }
            body += text(node.label, x: p.0+120, y: p.1+34, css: "nodeLabel")
        }
        body += "</svg>"
        return .init(format: format, svg: body, elementCount: visibleOrder.count + edges.count,
                     truncated: lines.count > maximumElements || order.count > maximumElements)
    }

    private static func renderSequence(_ lines: [String], format: String, plantUML: Bool) throws -> Rendered {
        var participants: [String] = []
        var messages: [(String, String, String, Bool)] = []
        func addParticipant(_ value: String) {
            let id = value.trimmingCharacters(in: .whitespaces)
            if !id.isEmpty && !participants.contains(id) { participants.append(id) }
        }
        for line in lines.prefix(maximumElements) {
            let lower = line.lowercased()
            if lower.hasPrefix("participant ") || lower.hasPrefix("actor ") {
                let remainder = line.split(separator: " ", maxSplits: 1).last.map(String.init) ?? ""
                let parts = remainder.components(separatedBy: " as ")
                addParticipant(parts.last ?? remainder)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let relation = String(line[..<colon]), label = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let arrows = ["-->>", "->>", "-->", "->", "<--", "<-"]
            guard let arrow = arrows.first(where: { relation.contains($0) }) else { continue }
            let pair = relation.components(separatedBy: arrow)
            guard pair.count == 2 else { continue }
            let a = cleanParticipant(pair[0]), b = cleanParticipant(pair[1])
            addParticipant(a); addParticipant(b)
            messages.append((a, b, label, arrow.contains("--")))
        }
        guard !participants.isEmpty else { throw malformed(L10n.text("没有识别到可渲染的参与者或消息。", "No renderable participants or messages were found.")) }
        let count = min(participants.count, 20)
        let visible = Array(participants.prefix(count))
        let width = max(640.0, Double(count) * 180.0 + 80)
        let height = max(240.0, Double(messages.count) * 72.0 + 150)
        var xByName: [String: Double] = [:]
        var body = svgHeader(width: width, height: height)
        for (index, name) in visible.enumerated() {
            let x = 70.0 + Double(index) * 180.0
            xByName[name] = x + 60
            body += #"<rect x="\#(x)" y="25" width="120" height="44" rx="8" class="node"/>"#
            body += text(name, x: x+60, y: 52, css: "nodeLabel")
            body += #"<line x1="\#(x+60)" y1="69" x2="\#(x+60)" y2="\#(height-30)" class="lifeline"/>"#
        }
        for (index, message) in messages.prefix(maximumElements).enumerated() {
            guard let x1=xByName[message.0], let x2=xByName[message.1] else { continue }
            let y=105.0+Double(index)*72.0
            body += #"<line x1="\#(x1)" y1="\#(y)" x2="\#(x2)" y2="\#(y)" class="\#(message.3 ? "dashed" : "edge")" marker-end="url(#arrow)"/>"#
            body += text(message.2, x: (x1+x2)/2, y: y-9, css: "edgeLabel")
        }
        body += "</svg>"
        return .init(format: format, svg: body, elementCount: visible.count + messages.count,
                     truncated: participants.count > visible.count || lines.count > maximumElements)
    }

    private static func renderDrawIO(_ source: String) throws -> Rendered {
        guard let data = source.data(using: .utf8) else { throw malformed(L10n.text("Draw.io XML 编码无效。", "Invalid Draw.io XML encoding.")) }
        let delegate = DrawIOParser()
        let parser = XMLParser(data: data); parser.delegate = delegate
        guard parser.parse() else {
            let parserDetail = parser.parserError?.localizedDescription ?? L10n.text("无法解析", "cannot parse")
            throw malformed(L10n.text("Draw.io XML 格式错误：\(parserDetail)", "Draw.io XML error: \(parserDetail)"))
        }
        var graph = delegate
        if graph.nodes.isEmpty, !graph.diagramText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let decoded = try decodeDrawIOPayload(graph.diagramText)
            let inner = DrawIOParser()
            let innerParser = XMLParser(data: decoded); innerParser.delegate = inner
            guard innerParser.parse() else { throw malformed(L10n.text("Draw.io 压缩图表内容无法解析。", "Cannot parse the compressed Draw.io diagram content.")) }
            graph = inner
        }
        let nodes = Array(graph.nodes.values.prefix(maximumElements))
        guard !nodes.isEmpty else { throw malformed(L10n.text("Draw.io 文件中没有可显示的图形。", "This Draw.io file has no shapes to display.")) }
        let maxX = nodes.map { $0.x+$0.width }.max() ?? 800
        let maxY = nodes.map { $0.y+$0.height }.max() ?? 600
        let width=max(400,maxX+40), height=max(240,maxY+40)
        var body=svgHeader(width:width,height:height)
        for edge in graph.edges.prefix(maximumElements) {
            guard let a=graph.nodes[edge.source], let b=graph.nodes[edge.target] else { continue }
            let x1=a.x+a.width/2, y1=a.y+a.height/2, x2=b.x+b.width/2, y2=b.y+b.height/2
            body += #"<line x1="\#(x1)" y1="\#(y1)" x2="\#(x2)" y2="\#(y2)" class="edge" marker-end="url(#arrow)"/>"#
            if !edge.label.isEmpty { body += text(edge.label,x:(x1+x2)/2,y:(y1+y2)/2-8,css:"edgeLabel") }
        }
        for node in nodes {
            if node.style.contains("ellipse") { body += #"<ellipse cx="\#(node.x+node.width/2)" cy="\#(node.y+node.height/2)" rx="\#(node.width/2)" ry="\#(node.height/2)" class="node"/>"# }
            else { body += #"<rect x="\#(node.x)" y="\#(node.y)" width="\#(node.width)" height="\#(node.height)" rx="8" class="node"/>"# }
            body += text(stripHTML(node.label),x:node.x+node.width/2,y:node.y+node.height/2+5,css:"nodeLabel")
        }
        body += "</svg>"
        let truncated=graph.nodes.count>maximumElements || graph.edges.count>maximumElements
        return .init(format:"Draw.io",svg:body,elementCount:nodes.count+min(graph.edges.count,maximumElements),truncated:truncated)
    }

    private static func decodeDrawIOPayload(_ value: String) throws -> Data {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let unescaped = trimmed.removingPercentEncoding ?? trimmed
        guard let compressed = Data(base64Encoded: unescaped, options: .ignoreUnknownCharacters), !compressed.isEmpty else {
            throw malformed(L10n.text("Draw.io 压缩内容不是有效的 Base64 数据。", "Draw.io compressed content is not valid Base64 data."))
        }
        var capacity = 64 * 1024
        let limit = 5 * 1024 * 1024
        while capacity <= limit {
            var output = [UInt8](repeating: 0, count: capacity)
            let decoded = compressed.withUnsafeBytes { source in
                guard let address = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(&output, capacity, address, compressed.count, nil, COMPRESSION_ZLIB)
            }
            if decoded > 0 && decoded < capacity { return Data(output.prefix(decoded)) }
            capacity *= 2
        }
        throw malformed(L10n.text("Draw.io 压缩内容损坏或解压后超过 5 MiB。", "Draw.io compressed content is corrupt or expands beyond 5 MiB."))
    }

    private static func meaningfulLines(_ source: String, commentPrefix: String) -> [String] {
        source.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(commentPrefix) }
    }

    private static func splitArrow(_ line: String) -> (left:String,right:String,label:String)? {
        for arrow in ["-.->", "-->", "==>", "---", "..>"] where line.contains(arrow) {
            let pair=line.components(separatedBy:arrow); guard pair.count==2 else { continue }
            var right=pair[1].trimmingCharacters(in:.whitespaces), label=""
            if right.hasPrefix("|"), let end=right.dropFirst().firstIndex(of:"|") {
                label=String(right[right.index(after:right.startIndex)..<end]); right=String(right[right.index(after:end)...]).trimmingCharacters(in:.whitespaces)
            }
            return (pair[0].trimmingCharacters(in:.whitespaces),right,label)
        }
        return nil
    }

    private static func parseNode(_ token:String) -> Node {
        let value=token.trimmingCharacters(in:.whitespaces)
        let id=String(value.prefix { $0.isLetter || $0.isNumber || "_.-".contains($0) })
        guard !id.isEmpty else { return .init(id:"",label:"",shape:.box) }
        let remainder=String(value.dropFirst(id.count)).trimmingCharacters(in:.whitespaces)
        if remainder.hasPrefix("{") && remainder.hasSuffix("}") { return .init(id:id,label:String(remainder.dropFirst().dropLast()),shape:.diamond) }
        if remainder.hasPrefix("(") && remainder.hasSuffix(")") { return .init(id:id,label:String(remainder.dropFirst().dropLast()),shape:.round) }
        if remainder.hasPrefix("[") && remainder.hasSuffix("]") { return .init(id:id,label:String(remainder.dropFirst().dropLast()),shape:.box) }
        return .init(id:id,label:id,shape:.box)
    }

    private static func cleanParticipant(_ value:String)->String {
        value.trimmingCharacters(in:.whitespaces).replacingOccurrences(of:#"^[+\-*]+|[+\-*]+$"#,with:"",options:.regularExpression)
    }
    private static func malformed(_ detail:String)->PreviewFailure { .malformedText(L10n.text("图表格式错误：\(detail)", "Invalid diagram: \(detail)")) }
    private static func stripHTML(_ value:String)->String { value.replacingOccurrences(of:#"<[^>]+>"#,with:"",options:.regularExpression) }
    private static func escaped(_ value:String)->String { value.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;") }
    private static func text(_ value:String,x:Double,y:Double,css:String)->String { #"<text x="\#(x)" y="\#(y)" class="\#(css)" text-anchor="middle">\#(escaped(value))</text>"# }
    private static func svgHeader(width:Double,height:Double)->String { #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(width)" height="\#(height)" viewBox="0 0 \#(width) \#(height)"><defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="rgb(100,116,139)"/></marker><style>.node{fill:rgb(239,246,255);stroke:rgb(59,130,246);stroke-width:2}.nodeLabel{font:15px -apple-system,BlinkMacSystemFont,sans-serif;fill:rgb(23,32,51)}.edge,.dashed{stroke:rgb(100,116,139);stroke-width:2;fill:none}.dashed{stroke-dasharray:7 5}.lifeline{stroke:rgb(148,163,184);stroke-width:1.5;stroke-dasharray:5 5}.edgeLabel{font:13px -apple-system,BlinkMacSystemFont,sans-serif;fill:rgb(71,85,105)}</style></defs><rect width="100%" height="100%" fill="rgb(255,255,255)"/>"# }

    private struct Rendered { let format:String; let svg:String; let elementCount:Int; let truncated:Bool }
    private enum Shape { case box,round,diamond }
    private struct Node { let id:String; let label:String; let shape:Shape }
    private struct Edge { let source:String; let target:String; let label:String }
}

private final class DrawIOParser: NSObject, XMLParserDelegate {
    struct Box { let id:String; let label:String; let style:String; var x=0.0; var y=0.0; var width=120.0; var height=60.0 }
    struct Link { let source:String; let target:String; let label:String }
    var nodes:[String:Box]=[:]; var edges:[Link]=[]; var diagramText=""
    private var currentID:String?
    private var diagramDepth=0
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String:String] = [:]) {
        if elementName=="diagram" { diagramDepth += 1 }
        if elementName=="mxCell" {
            currentID=a["id"]
            if a["vertex"]=="1", let id=a["id"] { nodes[id]=Box(id:id,label:a["value"] ?? "",style:a["style"] ?? "") }
            if a["edge"]=="1", let source=a["source"], let target=a["target"] { edges.append(.init(source:source,target:target,label:a["value"] ?? "")) }
        } else if elementName=="mxGeometry", let id=currentID, var box=nodes[id] {
            box.x=Double(a["x"] ?? "") ?? 0; box.y=Double(a["y"] ?? "") ?? 0
            box.width=Double(a["width"] ?? "") ?? 120; box.height=Double(a["height"] ?? "") ?? 60
            nodes[id]=box
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if diagramDepth > 0 { diagramText += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName=="mxCell" { currentID=nil }
        if elementName=="diagram" { diagramDepth=max(0,diagramDepth-1) }
    }
}
