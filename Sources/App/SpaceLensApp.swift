import SwiftUI
import AppKit

@main
struct SpaceLensApp: App {
    var body: some Scene {
        WindowGroup("SpaceLens") { SpaceLensHomeView() }
            .windowStyle(.titleBar)
    }
}

private struct SpaceLensHomeView: View {
    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "版本 \(version)（\(build)）"
    }

    private var extensionIsEmbedded: Bool {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else { return false }
        return FileManager.default.fileExists(atPath: plugInsURL.appendingPathComponent("SpaceLensPreview.appex").path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SpaceLens").font(.largeTitle.bold())
                    Text("按下空格，多看一点。").foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Label(extensionIsEmbedded ? "预览扩展已安装" : "未找到预览扩展",
                          systemImage: extensionIsEmbedded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(extensionIsEmbedded ? .green : .orange)
                    Text(versionText).font(.caption).foregroundColor(.secondary)
                }
            }
            Divider()
            Text("本地快速预览").font(.headline)
            HStack(alignment: .top, spacing: 12) {
                supportCard("文件与归档", "文件夹、ZIP、TAR、GZ、BZ2、XZ", "folder")
                supportCard("文本与文档", "代码、配置、Markdown、Notebook、TeX", "doc.text")
                supportCard("数据与图表", "JSON、plist、SQLite、Parquet、Arrow、Avro、图表", "tablecells")
            }
            Text("图片、PDF、音视频等格式继续使用 macOS 原生预览。SpaceLens 只提供 Quick Look，不会成为这些文件的双击打开应用。")
                .font(.callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("创建验收文件…", action: createSample).keyboardShortcut(.defaultAction)
                Button("打开系统设置", action: openSettings)
                Button("在 Finder 中显示 SpaceLens", action: revealApplication)
            }
            Spacer(minLength: 0)
            HStack {
                Label("所有预览均在本机处理", systemImage: "lock.shield")
                Spacer()
                Text("无需账号 · 无文件上传")
            }
            .font(.caption).foregroundColor(.secondary)
        }
        .padding(28)
        .frame(minWidth: 720, idealWidth: 760, minHeight: 430, idealHeight: 450)
    }

    private func supportCard(_ title: String, _ detail: String, _ symbol: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.headline)
                Text(detail).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
        }
        .frame(maxWidth: .infinity)
    }

    private func createSample() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Hello.spacelens"
        panel.title = "保存 SpaceLens 验收文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try "SpaceLens 验收文件\n\n如果预览顶部出现 SpaceLens · 验收文件，说明预览扩展工作正常。\n\n中文、English、emoji 👀\n".write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func openSettings() {
        guard let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
        NSWorkspace.shared.open(settings)
    }

    private func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
