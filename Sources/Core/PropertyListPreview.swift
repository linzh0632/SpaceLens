import Foundation
import CoreFoundation

enum PropertyListPreview {
    private static let maximumBytes = 20 * 1024 * 1024
    private static let maximumNodes = 10_000
    private static let maximumDepth = 50

    static func load(_ url: URL) throws -> PreviewSnapshot {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else {
            throw PreviewFailure.malformedText("属性列表超过 20 MiB 的安全读取上限。")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try load(data: data, name: url.lastPathComponent)
    }

    /// Entry point for content already in memory, e.g. a plist read out of an archive.
    static func load(data: Data, name: String) throws -> PreviewSnapshot {
        guard data.count <= maximumBytes else {
            throw PreviewFailure.malformedText("属性列表超过 20 MiB 的安全读取上限。")
        }
        try Task.checkCancellation()
        var format = PropertyListSerialization.PropertyListFormat.xml
        let value: Any
        do {
            value = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        } catch {
            throw PreviewFailure.malformedText("属性列表格式错误：\(error.localizedDescription)")
        }
        var budget = NodeBudget(remaining: maximumNodes)
        let root = build(value, key: "根", depth: 0, budget: &budget)
        let formatName: String
        switch format {
        case .binary: formatName = "Binary plist"
        case .openStep: formatName = "OpenStep plist"
        default: formatName = "XML plist"
        }
        let truncated = budget.truncated
        return PreviewSnapshot(
            title: name,
            summary: "SpaceLens · \(formatName) · 结构化预览\(truncated ? " · 已限制为 \(maximumNodes) 个节点/\(maximumDepth) 层" : "")",
            body: "",
            truncated: truncated,
            contentKind: .structured,
            structuredItems: [root],
            language: "Property List"
        )
    }

    private static func build(_ value: Any, key: String, depth: Int,
                              budget: inout NodeBudget) -> PreviewSnapshot.StructuredItem {
        guard budget.remaining > 0 else {
            budget.truncated = true
            return .init(key: key, type: "已截断", value: "达到节点上限")
        }
        budget.remaining -= 1
        guard depth < maximumDepth else {
            budget.truncated = true
            return .init(key: key, type: "已截断", value: "达到深度上限")
        }
        if let dictionary = value as? [String: Any] {
            let children = dictionary.keys.sorted().map {
                build(dictionary[$0]!, key: $0, depth: depth + 1, budget: &budget)
            }
            return .init(key: key, type: "字典", children: children)
        }
        if let array = value as? [Any] {
            let children = array.enumerated().map {
                build($0.element, key: "[\($0.offset)]", depth: depth + 1, budget: &budget)
            }
            return .init(key: key, type: "数组", children: children)
        }
        if let data = value as? Data {
            return .init(key: key, type: "数据", value: "\(data.count) 字节")
        }
        if let date = value as? Date {
            return .init(key: key, type: "日期", value: ISO8601DateFormatter().string(from: date))
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .init(key: key, type: "布尔值", value: number.boolValue ? "true" : "false")
            }
            return .init(key: key, type: "数字", value: number.stringValue)
        }
        if let string = value as? String {
            return .init(key: key, type: "字符串", value: clipped(string))
        }
        return .init(key: key, type: "未知", value: clipped(String(describing: value)))
    }

    private static func clipped(_ value: String) -> String {
        value.count <= 500 ? value : String(value.prefix(500)) + "…"
    }

    private struct NodeBudget {
        var remaining: Int
        var truncated = false
    }
}
