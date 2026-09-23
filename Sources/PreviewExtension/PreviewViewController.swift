import AppKit
import QuickLookUI
import OSLog

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let heading = NSTextField(labelWithString: "SpaceLens")
    private let detail = NSTextField(labelWithString: "正在读取…")
    private let text = NSTextView()
    private let logger = Logger(subsystem: "io.github.linzh0632.SpaceLens", category: "preview")
    private var generation = UUID()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        root.wantsLayer = true
        heading.font = .systemFont(ofSize: 23, weight: .semibold)
        heading.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        for child in [heading, detail, scroll] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            heading.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            detail.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            detail.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 18),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24)
        ])
        view = root
        preferredContentSize = NSSize(width: 720, height: 480)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        _ = view
        let request = UUID()
        generation = request
        heading.stringValue = url.lastPathComponent
        detail.stringValue = "SpaceLens · 正在读取…"
        text.string = ""
        let worker = Task.detached(priority: .userInitiated) { try PreviewLoader.load(url) }
        do {
            let snapshot = try await withTaskCancellationHandler(operation: {
                try await worker.value
            }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard generation == request else { return }
            heading.stringValue = snapshot.title
            detail.stringValue = snapshot.summary
            text.string = snapshot.body
            logger.notice("SpaceLens preview rendered; truncated=\(snapshot.truncated)")
        } catch {
            guard generation == request else { return }
            if error is CancellationError { throw error }
            detail.stringValue = "SpaceLens · 无法读取"
            text.string = error.localizedDescription
            logger.error("SpaceLens preview failed: \(error.localizedDescription, privacy: .private)")
        }
    }
}
