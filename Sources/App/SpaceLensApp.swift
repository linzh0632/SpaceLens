import SwiftUI
import AppKit
import OSLog
import ServiceManagement

private let appLogger = Logger(subsystem: "io.github.linzh0632.SpaceLens", category: "app")

private enum SpaceLensPreference {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let checkForUpdatesAutomatically = "checkForUpdatesAutomatically"
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

/// Registers the app as a login item, so previews are available right after signing in.
/// `SMAppService` needs macOS 13; on macOS 12 the settings row reports that instead.
private enum LaunchAtLogin {
    static var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns whether the requested state is now in effect.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            appLogger.notice("Login item set to \(enabled, privacy: .public)")
        } catch {
            appLogger.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        return isEnabled == enabled
    }
}

/// Asks GitHub for the latest release. This is the only network request SpaceLens makes, and it is
/// limited to a version comparison: no file, file name or usage data is sent.
@MainActor
private final class UpdateCenter: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case failed
    }

    static let shared = UpdateCenter()
    private static let releaseEndpoint = "https://api.github.com/repos/linzh0632/SpaceLens/releases/latest"

    @Published private(set) var status: Status = .idle

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var versionText: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(currentVersion)（\(build)）"
    }

    func check() async {
        guard status != .checking, let url = URL(string: Self.releaseEndpoint) else { return }
        status = .checking
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                appLogger.notice("Update check returned HTTP \(code, privacy: .public)")
                status = .failed
                return
            }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let tag = (object?["tag_name"] as? String) ?? ""
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard !latest.isEmpty else {
                status = .failed
                return
            }
            let newer = Self.isNewer(latest, than: currentVersion)
            appLogger.notice("Update check: latest \(latest, privacy: .public), newer \(newer, privacy: .public)")
            status = newer ? .available(latest) : .upToDate
        } catch {
            appLogger.notice("Update check failed: \(error.localizedDescription, privacy: .public)")
            status = .failed
        }
    }

    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}

@MainActor
private final class SpaceLensAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Checking for updates is opt-in, so an unset preference simply means "off".
        MenuBarController.shared.setEnabled(UserDefaults.standard.bool(forKey: SpaceLensPreference.showMenuBarIcon))
        let status = PreviewExtensionElection.activateForThisSession()
        appLogger.notice("Launch check: preview extension status \(String(describing: status), privacy: .public)")
        SpaceLensExtensionAlert.presentIfNeeded(status)
        if UserDefaults.standard.bool(forKey: SpaceLensPreference.checkForUpdatesAutomatically) {
            Task { await UpdateCenter.shared.check() }
        }
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
    private static let projectURL = "https://github.com/linzh0632/SpaceLens"

    static func openSystemSettings() {
        guard let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
        NSWorkspace.shared.open(settings)
    }

    static func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func openProjectPage() {
        open(projectURL)
    }

    static func openReleasesPage() {
        open(projectURL + "/releases")
    }

    private static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

@main
struct SpaceLensApp: App {
    @NSApplicationDelegateAdaptor(SpaceLensAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("SpaceLens 设置") {
            SpaceLensSettingsView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case features
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .features: return "功能设置"
        case .general: return "通用设置"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .features: return "slider.horizontal.3"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

private struct SpaceLensSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SpaceLensPreference.showMenuBarIcon) private var showMenuBarIcon = false
    @AppStorage(SpaceLensPreference.checkForUpdatesAutomatically) private var checkForUpdates = false
    @State private var page: SettingsPage? = .features
    @State private var extensionStatus: PreviewExtensionElection.Status?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @ObservedObject private var updates = UpdateCenter.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            // The scroll view paints its own background over anything placed behind it, so the content
            // fill is drawn inside it and stretched to at least the visible height.
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(currentPage.title)
                            .font(.system(size: 22, weight: .bold))
                        switch currentPage {
                        case .features: featuresPage
                        case .general: generalPage
                        case .about: aboutPage
                        }
                    }
                    .padding(Self.pageInset)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    .background(contentFill)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 620)
        // macOS defaults to checkboxes; the switch matches the rest of the row layout.
        .toggleStyle(.switch)
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

    /// Shared inset, so the sidebar title lines up with the page title.
    private static let pageInset: CGFloat = 28

    // The colours are explicit because the system background colours resolve to the same value
    // behind a scroll view, which would leave the sidebar and the content indistinguishable.
    private var sidebarFill: Color {
        colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.93)
    }

    private var contentFill: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(white: 1.0)
    }

    private var cardFill: Color {
        colorScheme == .dark ? Color(white: 0.17) : Color(white: 0.97)
    }

    private var currentPage: SettingsPage { page ?? .features }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SpaceLens")
                .font(.system(size: 20, weight: .semibold))
                .padding(.horizontal, 12)
                // Same inset as the page title, so both headings sit on one line.
                .padding(.top, Self.pageInset)
                .padding(.bottom, 14)
            ForEach(SettingsPage.allCases) { item in
                sidebarRow(item)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: 208)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarFill.ignoresSafeArea())
    }

    private func sidebarRow(_ item: SettingsPage) -> some View {
        let selected = currentPage == item
        return Button {
            page = item
        } label: {
            Label(item.title, systemImage: item.symbol)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 功能设置

    private var featuresPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            section("预览扩展") {
                card {
                    settingRow("状态") {
                        Label(extensionStatusText, systemImage: extensionStatusSymbol)
                            .foregroundColor(extensionStatusColor)
                    }
                    divider
                    settingRow("重新检查") {
                        Button("重新检查") {
                            Task { extensionStatus = await PreviewExtensionElection.currentState() }
                        }
                    }
                    divider
                    settingRow("系统设置") {
                        Button("打开系统设置", action: SpaceLensActions.openSystemSettings)
                    }
                }
                helper("SpaceLens 只在运行时提供预览：退出应用会停用预览扩展，重新打开 SpaceLens 后自动恢复。如果你在系统设置中手动停用了扩展，SpaceLens 不会覆盖这个选择。")
            }
            section("预览范围") {
                card {
                    settingRow("文件与归档") {
                        value("文件夹、ZIP、TAR、GZ、BZ2、XZ")
                    }
                    divider
                    settingRow("文本与文档") {
                        value("代码、配置、Markdown、Notebook、TeX")
                    }
                    divider
                    settingRow("数据与图表") {
                        value("JSON、plist、SQLite、Parquet、Arrow、Avro、图表")
                    }
                }
                helper("图片、PDF、音视频等格式继续使用 macOS 原生预览，SpaceLens 不会成为这些文件的双击打开应用。归档内的 SQLite 与列式数据不在右侧窗格预览，以免写入磁盘。")
            }
        }
    }

    // MARK: - 通用设置

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            section("外观") {
                card {
                    settingRow("在菜单栏显示") {
                        Toggle("", isOn: $showMenuBarIcon).labelsHidden()
                            .controlSize(.mini)
                    }
                }
                helper("在菜单栏提供打开 SpaceLens、进入 Quick Look 系统设置和退出应用的入口。")
            }
            section("启动") {
                card {
                    settingRow("开机自启动") {
                        if LaunchAtLogin.isSupported {
                            Toggle("", isOn: launchAtLoginBinding).labelsHidden()
                                .controlSize(.mini)
                        } else {
                            value("需要 macOS 13 或更高版本")
                        }
                    }
                }
                helper("登录 Mac 后自动启动 SpaceLens，这样无需手动打开就能使用预览。")
            }
            section("更新") {
                card {
                    settingRow("自动检查更新") {
                        Toggle("", isOn: $checkForUpdates).labelsHidden()
                            .controlSize(.mini)
                    }
                    divider
                    settingRow("检查更新") {
                        Button("立即检查") {
                            Task { await updates.check() }
                        }
                    }
                }
                helper(updateHelperText)
            }
        }
    }

    // MARK: - 关于

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            card {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SpaceLens")
                            .font(.system(size: 20, weight: .semibold))
                        Text("按下空格，多看一点。")
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                divider
                settingRow("当前版本") {
                    HStack(spacing: 10) {
                        Text(updates.versionText).foregroundColor(.secondary)
                        Button("检查更新") {
                            Task { await updates.check() }
                        }
                    }
                }
            }
            section("隐私与许可") {
                card {
                    settingRow("预览处理") {
                        value("全部在本机完成")
                    }
                    divider
                    settingRow("网络请求") {
                        value(checkForUpdates ? "仅检查更新时访问 GitHub" : "已关闭")
                    }
                    divider
                    settingRow("项目主页") {
                        Button("在 GitHub 上查看", action: SpaceLensActions.openProjectPage)
                    }
                }
                helper("SpaceLens 使用 MIT License。不创建账号、不包含遥测、不上传文件；预览内容不会离开你的 Mac。")
            }
        }
    }

    // MARK: - 绑定

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { requested in
                launchAtLogin = LaunchAtLogin.setEnabled(requested) ? requested : LaunchAtLogin.isEnabled
            }
        )
    }

    // MARK: - 状态文案

    private var extensionStatusText: String {
        switch extensionStatus {
        case .enabled: return "预览已启用"
        case .disabled: return "预览已停用"
        case .notEmbedded: return "未找到预览扩展"
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

    private var updateHelperText: String {
        switch updates.status {
        case .idle:
            return checkForUpdates
                ? "启动时会向 GitHub 查询最新版本号，不发送文件、文件名或使用数据。"
                : "已关闭自动检查；仍可手动检查更新。"
        case .checking:
            return "正在检查更新…"
        case .upToDate:
            return "已是最新版本。"
        case .available(let version):
            return "发现新版本 \(version)，可在 GitHub 的发布页面查看。"
        case .failed:
            return "检查更新失败：可能没有网络连接，或项目尚未在 GitHub 发布正式版本。"
        }
    }

    // MARK: - 组件

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    private func settingRow<Content: View>(_ title: String,
                                           @ViewBuilder trailing: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Divider().padding(.leading, 16)
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.trailing)
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
