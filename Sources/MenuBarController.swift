import AppKit

// Keep the status item text-only; the native popover follows the system appearance.
@MainActor
final class MenuBarController: NSObject {
    var onRefresh: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let percent = NSTextField(labelWithString: "—")
    private let countdown = NSTextField(labelWithString: "正在读取…")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let progress = QuotaProgressView()
    private let refreshButton = NSButton(title: "立即刷新", target: nil, action: nil)

    override init() {
        super.init()
        item.button?.image = nil
        item.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityLabel("Codex 每周额度")
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 286)
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 286))
        popover.contentViewController = controller

        let heading = NSTextField(labelWithString: "Codex")
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        percent.font = .monospacedDigitSystemFont(ofSize: 34, weight: .medium)
        let caption = NSTextField(labelWithString: "本周剩余")
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        let resetLabel = NSTextField(labelWithString: "距离重置")
        resetLabel.textColor = .secondaryLabelColor
        resetLabel.font = .systemFont(ofSize: 12)
        countdown.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let resetRow = NSStackView(views: [resetLabel, NSView(), countdown])
        resetRow.orientation = .horizontal
        message.font = .systemFont(ofSize: 11)
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 2

        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        let settings = NSButton(title: "设置…", target: self, action: #selector(settings))
        let quit = NSButton(title: "退出", target: self, action: #selector(quit))
        for button in [refreshButton, settings, quit] {
            button.isBordered = false
            button.alignment = .left
            button.font = .systemFont(ofSize: 13)
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: [heading, percent, caption, progress, resetRow, message,
                                       separator, refreshButton, settings, quit])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.setCustomSpacing(12, after: caption)
        stack.setCustomSpacing(12, after: progress)
        stack.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: -16),
            progress.heightAnchor.constraint(equalToConstant: 5)
        ])
        for view in [progress, resetRow, message, separator, refreshButton, settings, quit] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        update(quota: nil, error: nil, refreshing: true)
    }

    func update(quota: WeeklyQuota?, error: String?, refreshing: Bool, now: Date = Date()) {
        let title = MenuBarText.title(quota: quota, error: error, now: now)
        if item.button?.title != title {
            item.button?.title = title
            item.button?.setAccessibilityValue(title)
        }
        refreshButton.isEnabled = !refreshing
        refreshButton.title = refreshing ? "正在刷新…" : "立即刷新"
        if let quota {
            percent.stringValue = "\(Int(quota.remainingPercent.rounded()))%"
            countdown.stringValue = MenuBarText.countdown(to: quota.resetsAt, now: now)
            progress.fraction = quota.remainingPercent / 100
            let reset = quota.resetsAt.formatted(date: .abbreviated, time: .shortened)
            item.button?.toolTip = "Codex 本周剩余 \(percent.stringValue)\n重置时间：\(reset)"
        } else {
            percent.stringValue = "—"
            countdown.stringValue = error == nil ? "正在读取…" : "暂不可用"
            progress.fraction = 0
            item.button?.toolTip = error ?? "正在读取 Codex 每周额度"
        }
        let expired = quota.map { $0.resetsAt <= now } ?? false
        message.stringValue = error.map { quota == nil ? $0 : "刷新失败，显示上次数据：\($0)" }
            ?? (expired ? "等待额度更新" : "")
        message.isHidden = message.stringValue.isEmpty
        let size = NSSize(width: 280, height: message.isHidden ? 286 : 320)
        if popover.contentSize != size { popover.contentSize = size }
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    @objc private func refresh() { onRefresh?() }
    @objc private func settings() { popover.performClose(nil); onSettings?() }
    @objc private func quit() { onQuit?() }
}

struct MenuBarText {
    static func title(quota: WeeklyQuota?, error: String?, now: Date = Date()) -> String {
        guard let quota else { return error == nil ? "Codex · …" : "Codex · —" }
        return "\(Int(quota.remainingPercent.rounded()))% · \(countdown(to: quota.resetsAt, now: now))"
    }

    static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(Int(date.timeIntervalSince(now)), 0)
        if seconds == 0 { return "待重置" }
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 { return "\(days)天\(hours)时" }
        if hours > 0 { return "\(hours)时\(minutes)分" }
        return minutes > 0 ? "\(minutes)分" : "不足1分"
    }
}

private final class QuotaProgressView: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5).fill()
        NSColor.secondaryLabelColor.setFill()
        let fill = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(fraction), height: bounds.height)
        NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()
    }
}
