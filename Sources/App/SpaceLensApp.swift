import SwiftUI
import AppKit

private enum SpaceLensPreference {
    static let showMenuBarIcon = "showMenuBarIcon"
}

@MainActor
private final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?

    func setEnabled(_ enabled: Bool) {
        if enabled {
            installIfNeeded()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "SpaceLens")
            button.image?.isTemplate = true
            button.toolTip = "SpaceLens"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "打开 SpaceLens", action: #selector(openSpaceLens), keyEquivalent: "")
        menu.addItem(withTitle: "打开 Quick Look 设置", action: #selector(openSystemSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 SpaceLens", action: #selector(quitSpaceLens), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func openSpaceLens() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openSystemSettings() {
        SpaceLensActions.openSystemSettings()
    }

    @objc private func quitSpaceLens() {
        NSApp.terminate(nil)
    }
}

private final class SpaceLensAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarController.shared.setEnabled(UserDefaults.standard.bool(forKey: SpaceLensPreference.showMenuBarIcon))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private enum SpaceLensActions {
    static func openSystemSettings() {
        guard let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
        NSWorkspace.shared.open(settings)
    }

    static func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

}

@main
struct SpaceLensApp: App {
    @NSApplicationDelegateAdaptor(SpaceLensAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("SpaceLens 设置") {
            SpaceLensSettingsView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

private struct SpaceLensSettingsView: View {
    @AppStorage(SpaceLensPreference.showMenuBarIcon) private var showMenuBarIcon = false

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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                settingsSection
                extensionSection
                formatsSection
                privacyFooter
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 700, idealWidth: 760, minHeight: 540, idealHeight: 580)
        .onAppear {
            MenuBarController.shared.setEnabled(showMenuBarIcon)
        }
        .onChange(of: showMenuBarIcon) { enabled in
            MenuBarController.shared.setEnabled(enabled)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "viewfinder")
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 54, height: 54)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
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
        .padding(.bottom, 4)
    }

    private var settingsSection: some View {
        settingCard(title: "常规", symbol: "gearshape") {
            Toggle(isOn: $showMenuBarIcon) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("在菜单栏显示 SpaceLens")
                    Text("在菜单栏提供打开设置、进入 Quick Look 系统设置和退出应用的快捷入口。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var extensionSection: some View {
        settingCard(title: "Quick Look 扩展", symbol: "eye") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(extensionIsEmbedded ? "扩展已包含在当前应用中" : "当前应用中未找到扩展",
                          systemImage: extensionIsEmbedded ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(extensionIsEmbedded ? .primary : .orange)
                    Spacer()
                }
                Text("如果 Finder 中无法预览支持的文件，请在系统设置的登录项与扩展中确认 SpaceLens Quick Look 已启用。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("打开系统设置", action: SpaceLensActions.openSystemSettings)
                    Button("在 Finder 中显示应用", action: SpaceLensActions.revealApplication)
                }
            }
        }
    }

    private var formatsSection: some View {
        settingCard(title: "预览范围", symbol: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    formatColumn("文件与归档", "文件夹、ZIP、TAR、GZ、BZ2、XZ", "folder")
                    formatColumn("文本与文档", "代码、配置、Markdown、Notebook、TeX", "doc.text")
                    formatColumn("数据与图表", "JSON、plist、SQLite、Parquet、Arrow、Avro、图表", "tablecells")
                }
                Text("图片、PDF、音视频等格式继续使用 macOS 原生预览。SpaceLens 只提供 Quick Look，不会成为这些文件的双击打开应用。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyFooter: some View {
        HStack {
            Label("所有预览均在本机处理", systemImage: "lock.shield")
            Spacer()
            Text("无需账号 · 无文件上传")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
    }

    private func settingCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            Divider()
            content()
                .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.08)))
    }

    private func formatColumn(_ title: String, _ detail: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
