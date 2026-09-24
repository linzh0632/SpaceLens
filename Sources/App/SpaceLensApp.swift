import SwiftUI
import AppKit

@main
struct SpaceLensApp: App {
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
                Text("第二阶段 · 文件夹与 ZIP").font(.headline)
                Text("当前支持 .spacelens 验收文件、文件夹树和 ZIP 内容预览。图片、PDF、音视频继续使用系统预览。")
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
                Text("在 Finder 中选中验收文件、文件夹或 ZIP，按空格查看。")
                    .font(.callout).foregroundColor(.secondary).textSelection(.enabled)
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
        } catch {
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
