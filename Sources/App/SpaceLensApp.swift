import SwiftUI
import AppKit
import OSLog

private let appLogger = Logger(subsystem: "io.github.linzh0632.SpaceLens", category: "app")

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

/// Quick Look extensions are registered with the system and are not tied to the host app's
/// lifetime, so quitting SpaceLens would otherwise leave its previews active. The election state
/// below is the same store System Settings edits, reached through `pluginkit`.
private enum PreviewExtensionElection {
    /// Result of the launch-time check, so the app can tell the user when previews will not work.
    enum Status: Equatable {
        case enabled
        case disabled
        case notEmbedded
        case unavailable
    }

    static let identifier = "io.github.linzh0632.SpaceLens.Preview"
    /// Records that *this app* disabled the extension on its last quit, so a manual choice made in
    /// System Settings is never overridden on the next launch.
    private static let disabledOnQuitKey = "extensionDisabledOnQuit"
    private static let logger = Logger(subsystem: "io.github.linzh0632.SpaceLens", category: "lifecycle")

    /// The embedded extension, or `nil` when the bundle does not contain it.
    static var extensionURL: URL? {
        Bundle.main.builtInPlugInsURL?.appendingPathComponent("SpaceLensPreview.appex")
    }

    /// `nil` when the state cannot be read, so callers do not act on a guess.
    private static func isEnabled() -> Bool? {
        guard let output = run(["-m", "-v", "-i", identifier]) else { return nil }
        for line in output.split(separator: "\n") where line.contains(identifier) {
            // An explicit election marks the line with "-" (ignored) or "+" (elected for use).
            if line.hasPrefix("-") { return false }
            return true
        }
        return nil
    }

    /// Reads the current status without changing anything.
    static func status() -> Status {
        guard extensionURL != nil else { return .notEmbedded }
        guard let enabled = isEnabled() else { return .unavailable }
        return enabled ? .enabled : .disabled
    }

    /// Reads the status off the main thread for the settings UI.
    static func currentState() async -> Status {
        await Task.detached(priority: .utility) { PreviewExtensionElection.status() }.value
    }

    /// Launch check: confirms previews are actually available, re-enabling the extension when this
    /// app disabled it on the previous quit. Registration is retried once, because a lost
    /// registration and an unreadable state are indistinguishable on the first read.
    static func activateForThisSession() -> Status {
        guard let extensionURL else {
            logger.error("Preview extension is missing from the app bundle")
            return .notEmbedded
        }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: disabledOnQuitKey), run(["-e", "use", "-i", identifier]) != nil {
            defaults.set(false, forKey: disabledOnQuitKey)
            logger.notice("Quick Look extension re-enabled for this session")
        }
        if let enabled = isEnabled() { return enabled ? .enabled : .disabled }
        guard run(["-a", extensionURL.path]) != nil, let enabled = isEnabled() else {
            logger.error("Could not read the Quick Look extension state")
            return .unavailable
        }
        return enabled ? .enabled : .disabled
    }

    /// Disables the extension so that quitting the app also stops previews. If it is already
    /// ignored, that choice came from System Settings and is left untouched.
    static func suspendForQuit() {
        let defaults = UserDefaults.standard
        guard let enabled = isEnabled() else { return }
        guard enabled else {
            defaults.set(false, forKey: disabledOnQuitKey)
            return
        }
        guard run(["-e", "ignore", "-i", identifier]) != nil else {
            logger.error("Could not disable the Quick Look extension on quit")
            return
        }
        defaults.set(true, forKey: disabledOnQuitKey)
        logger.notice("Quick Look extension disabled on quit")
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            logger.error("pluginkit did not launch: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private final class SpaceLensAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarController.shared.setEnabled(UserDefaults.standard.bool(forKey: SpaceLensPreference.showMenuBarIcon))
        let status = PreviewExtensionElection.activateForThisSession()
        appLogger.notice("Launch check: preview extension status \(String(describing: status), privacy: .public)")
        SpaceLensExtensionAlert.presentIfNeeded(status)
    }

    func applicationWillTerminate(_ notification: Notification) {
        PreviewExtensionElection.suspendForQuit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Tells the user at launch when the preview extension is not active, because SpaceLens cannot
/// provide its previews in that state. Only shown when the check did not come back clean.
private enum SpaceLensExtensionAlert {
    static func presentIfNeeded(_ status: PreviewExtensionElection.Status) {
        guard status != .enabled else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        switch status {
        case .enabled:
            return
        case .disabled:
            alert.messageText = "SpaceLens 预览扩展当前已停用"
            alert.informativeText = "空格预览会使用 macOS 原生预览。若要让 SpaceLens 接管支持的文件类型，请在“系统设置 → 通用 → 登录项与扩展 → Quick Look”中启用它。"
        case .notEmbedded:
            alert.messageText = "未找到 SpaceLens 预览扩展"
            alert.informativeText = "当前应用包内缺少 SpaceLensPreview.appex，请重新安装 SpaceLens。"
        case .unavailable:
            alert.messageText = "无法确认预览扩展状态"
            alert.informativeText = "SpaceLens 未能读取 Quick Look 扩展的启用状态，预览可能不会生效。可以尝试重新安装应用或重新登录。"
        }
        let showsApp = status == .notEmbedded
        alert.addButton(withTitle: showsApp ? "在 Finder 中显示应用" : "打开系统设置")
        alert.addButton(withTitle: "好")
        // Present after the settings window has appeared, so the alert is not the only thing on screen.
        DispatchQueue.main.async {
            appLogger.notice("Showing preview extension warning for status \(String(describing: status), privacy: .public)")
            if alert.runModal() == .alertFirstButtonReturn {
                if showsApp {
                    SpaceLensActions.revealApplication()
                } else {
                    SpaceLensActions.openSystemSettings()
                }
            }
        }
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
    @State private var extensionStatus: PreviewExtensionElection.Status?

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "版本 \(version)（\(build)）"
    }

    private var extensionIsEmbedded: Bool {
        PreviewExtensionElection.extensionURL != nil
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
        .task {
            extensionStatus = await PreviewExtensionElection.currentState()
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
                    Label(extensionStatusText, systemImage: extensionStatusSymbol)
                        .foregroundColor(extensionStatusColor)
                    Spacer()
                    Button("重新检查") {
                        Task { extensionStatus = await PreviewExtensionElection.currentState() }
                    }
                    .controlSize(.small)
                }
                Text("SpaceLens 只在运行时提供预览：退出应用会停用预览扩展，重新打开 SpaceLens 后自动恢复。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("如果你在系统设置中手动停用了扩展，SpaceLens 不会在下次启动时覆盖这个选择。")
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

    private var extensionStatusText: String {
        switch extensionStatus {
        case .enabled: return "预览已启用"
        case .disabled: return "预览已停用"
        case .notEmbedded: return "当前应用中未找到预览扩展"
        case .unavailable: return "无法读取扩展状态"
        case nil: return "正在检查扩展状态…"
        }
    }

    private var extensionStatusSymbol: String {
        switch extensionStatus {
        case .enabled: return "checkmark.seal.fill"
        case .disabled: return "pause.circle.fill"
        case .notEmbedded: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle.fill"
        case nil: return "clock"
        }
    }

    private var extensionStatusColor: Color {
        switch extensionStatus {
        case .enabled: return .green
        case .disabled: return .orange
        case .notEmbedded: return .orange
        case .unavailable: return .secondary
        case nil: return .secondary
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
