import SwiftUI
import AppKit

@main
struct SpaceLensApp: App {
    @State private var message = "在 Finder 中选中验收文件，按空格查看。"
    var body: some Scene {
        WindowGroup("SpaceLens") {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "viewfinder").font(.system(size: 40)).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("SpaceLens").font(.largeTitle.bold())
                        Text("按下空格，多看一点。").foregroundColor(.secondary)
                    }
                }
                Divider()
                Text("第一阶段 · 预览接入原型").font(.headline)
                Text("当前支持 .spacelens 验收文件和文件夹浅层预览。图片、PDF、音视频继续使用系统预览。")
                Text("如果文件夹仍显示其他预览，请在系统设置的扩展管理中检查 SpaceLens 与现有预览扩展。")
                    .foregroundColor(.secondary)
                HStack {
                    Button("创建验收文件…", action: createSample).keyboardShortcut(.defaultAction)
                    Button("打开系统设置") {
                        if let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                            NSWorkspace.shared.open(settings)
                        }
                    }
                }
                Text(message).font(.callout).foregroundColor(.secondary).textSelection(.enabled)
                Spacer(minLength: 0)
                Text("本地处理 · 无需账号 · 无文件上传").font(.caption).foregroundColor(.secondary)
            }
            .padding(30).frame(width: 560, height: 390)
        }.windowStyle(.titleBar)
    }

    private func createSample() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Hello.spacelens"
        panel.title = "保存 SpaceLens 验收文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try "SpaceLens 验收文件\n\n如果预览顶部出现 SpaceLens · 验收文件，说明我们的扩展已经接管这个文件。\n\n中文、English、emoji 👀\n".write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            message = "已保存 \(url.lastPathComponent)。在 Finder 中按空格。"
        } catch { message = "保存失败：\(error.localizedDescription)" }
    }
}
