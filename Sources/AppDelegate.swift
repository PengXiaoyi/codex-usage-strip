import AppKit
import CoreGraphics
import Foundation
import ServiceManagement
import UserNotifications

enum StatusRingGeometry {
    static func displayedProgress(
        for percent: Double,
        diameter: Double,
        minimumGap: Double = 2,
        completeThreshold: Double = 99.5
    ) -> Double {
        let progress = min(max(percent, 0), 100) / 100
        guard progress > 0 else { return 0 }
        if percent >= completeThreshold { return 1 }

        let circumference = Double.pi * diameter
        let maximumVisibleProgress = max(0, 1 - minimumGap / circumference)
        return min(progress, maximumVisibleProgress)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UsageStripViewDelegate {
    private let preferences = AppPreferences.shared
    private let service = CodexQuotaService()
    private let appUpdateController = AppUpdateController()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem?
    private var materialView: NSVisualEffectView!
    private var usageView: UsageStripView!
    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var settingsController: SettingsWindowController?
    private var aboutController: AboutWindowController?
    private var lastNotifiedState: PaceState?
    private var isApplyingWindowFrame = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LegacyMigration.migrateApplicationSupport(preferences: preferences)
        do {
            try LaunchAtLoginManager.shared.repairRegistrationIfNeeded()
        } catch {
            showAlert(title: "开机启动修复失败", detail: error.localizedDescription)
        }
        if CommandLine.arguments.contains("--status-bar") {
            preferences.showDesktopCard = false
        }
        createPanel()
        createStatusItem()
        createAboutController()
        createSettingsController()
        restoreOrSetDefaultPosition()
        applyPreferences(rescheduleRefresh: true)
        enableLaunchAtLoginByDefaultIfNeeded()
        refreshNow()

        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.settingsController?.present() }
        }
        if CommandLine.arguments.contains("--show-about") {
            DispatchQueue.main.async { [weak self] in self?.aboutController?.present() }
        }

        tickTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(tickTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        tickTimer?.invalidate()
        service.stop()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    private func createPanel() {
        let size = preferences.displayMode.size
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        materialView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        materialView.autoresizingMask = [.width, .height]
        materialView.wantsLayer = true
        materialView.layer?.masksToBounds = true

        usageView = UsageStripView(frame: NSRect(origin: .zero, size: size))
        usageView.autoresizingMask = [.width, .height]
        usageView.delegate = self
        materialView.addSubview(usageView)
        panel.contentView = materialView
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.isVisible = true
    }

    private func createSettingsController() {
        let controller = SettingsWindowController()
        controller.onPreferencesChanged = { [weak self] in
            self?.applyPreferences(rescheduleRefresh: true)
        }
        controller.onLaunchAtLoginChanged = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled)
        }
        controller.onShowAbout = { [weak self] in
            self?.aboutController?.present()
        }
        controller.onAutomaticUpdateChecksChanged = { [weak self] enabled in
            self?.appUpdateController.setAutomaticallyChecksForUpdates(enabled)
        }
        settingsController = controller
    }

    private func createAboutController() {
        let controller = AboutWindowController()
        controller.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates(manual: true)
        }
        aboutController = controller
    }

    private func applyPreferences(rescheduleRefresh: Bool) {
        let selectedTheme = ThemeStore.shared.theme(id: preferences.themeID)
        usageView.theme = selectedTheme
        usageView.displayMode = preferences.displayMode
        usageView.phrases = preferences.phraseSet
        usageView.criticalThreshold = preferences.criticalThreshold
        usageView.backgroundImage = BackgroundAssetStore.currentImage(preferences: preferences)
        usageView.backgroundImageOpacity = preferences.backgroundImageOpacity
        usageView.backgroundImageMode = preferences.backgroundImageMode
        let isSystemTheme = selectedTheme.id.hasPrefix("system-")
        materialView.material = isSystemTheme ? .hudWindow : .titlebar
        materialView.blendingMode = isSystemTheme ? .behindWindow : .withinWindow
        materialView.state = isSystemTheme ? .active : .inactive
        materialView.isEmphasized = false
        materialView.layer?.cornerRadius = CGFloat(selectedTheme.cornerRadius)
        panel.alphaValue = CGFloat(preferences.overallOpacity)

        let oldFrame = panel.frame
        let mode = preferences.displayMode
        let size = preferences.windowSize(for: mode) ?? mode.size
        panel.minSize = mode.minimumSize
        panel.maxSize = mode.maximumSize
        let newOrigin = NSPoint(x: oldFrame.origin.x, y: oldFrame.maxY - size.height)
        isApplyingWindowFrame = true
        panel.setFrame(NSRect(origin: newOrigin, size: size), display: true, animate: true)
        isApplyingWindowFrame = false
        usageView.frame = NSRect(origin: .zero, size: size)
        usageView.bounds = NSRect(origin: .zero, size: mode.size)
        panel.invalidateCursorRects(for: usageView)
        updateStatusItem(rebuildMenu: true)
        applyWindowLevel()

        if preferences.notificationsEnabled {
            requestNotificationPermission()
        }
        if rescheduleRefresh { scheduleRefreshTimer() }
    }

    private func applyWindowLevel() {
        guard preferences.showDesktopCard else {
            panel.orderOut(nil)
            return
        }
        if preferences.alwaysOnTop {
            panel.level = .floating
        } else {
            let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow)) + 1
            panel.level = NSWindow.Level(rawValue: desktopLevel)
        }
        panel.orderFrontRegardless()
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: preferences.refreshInterval,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    private func checkForUpdates(manual: Bool) {
        if appUpdateController.isReady {
            aboutController?.setUpdateResult("已打开安全更新检查")
            appUpdateController.checkForUpdates()
            return
        }
        if manual {
            aboutController?.present()
            aboutController?.setUpdateResult("本地构建未注入更新源与 EdDSA 公钥")
        }
    }

    private func refreshNow() {
        if usageView.quota == nil { usageView.errorText = nil }
        service.refresh { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let quota):
                self.usageView.errorText = nil
                self.usageView.quota = quota
                self.notifyIfNeeded(quota)
            case .failure(let error):
                if self.usageView.quota == nil {
                    self.usageView.errorText = error.localizedDescription
                }
            }
            self.updateStatusItem()
        }
    }

    private func notifyIfNeeded(_ quota: WeeklyQuota) {
        guard preferences.notificationsEnabled else { return }
        let state = quota.paceState(criticalThreshold: preferences.criticalThreshold)
        defer { lastNotifiedState = state }
        guard state != lastNotifiedState, state == .fast || state == .critical else { return }

        let content = UNMutableNotificationContent()
        content.title = state == .critical ? "Codex 周额度接近耗尽" : "Codex 本周消耗偏快"
        content.body = PhraseEngine.phrase(for: quota, state: state, phrases: preferences.phraseSet)
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "quota-\(state.rawValue)", content: content, trigger: nil)
        )
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func enableLaunchAtLoginByDefaultIfNeeded() {
        guard !preferences.launchAtLoginConfigured else { return }
        if setLaunchAtLogin(true) {
            preferences.launchAtLoginConfigured = true
        }
    }

    @discardableResult
    private func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            try LaunchAtLoginManager.shared.setEnabled(enabled)
            preferences.launchAtLoginConfigured = true
            return true
        } catch {
            showAlert(title: "开机启动设置失败", detail: error.localizedDescription)
            return false
        }
    }

    private func restoreOrSetDefaultPosition() {
        if let saved = UserDefaults.standard.string(forKey: "windowOrigin") {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                let origin = NSPoint(x: parts[0], y: parts[1])
                if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -40, dy: -40).contains(origin) }) {
                    panel.setFrameOrigin(origin)
                    return
                }
            }
        }
        moveToBottomRight()
    }

    private func moveToBottomRight() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 24, y: frame.minY + 24))
    }

    func windowDidMove(_ notification: Notification) {
        let origin = panel.frame.origin
        UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: "windowOrigin")
    }

    func windowDidResize(_ notification: Notification) {
        guard !isApplyingWindowFrame else { return }
        preferences.setWindowSize(panel.frame.size, for: preferences.displayMode)
        usageView.bounds = NSRect(origin: .zero, size: preferences.displayMode.size)
        panel.invalidateCursorRects(for: usageView)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        snapToNearestEdge()
    }

    func windowDidEndLiveMove(_ notification: Notification) {
        snapToNearestEdge()
    }

    private func snapToNearestEdge() {
        guard let screen = panel.screen else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        let snap: CGFloat = 18
        if abs(frame.minX - visible.minX) < snap { frame.origin.x = visible.minX + 8 }
        if abs(frame.maxX - visible.maxX) < snap { frame.origin.x = visible.maxX - frame.width - 8 }
        if abs(frame.minY - visible.minY) < snap { frame.origin.y = visible.minY + 8 }
        if abs(frame.maxY - visible.maxY) < snap { frame.origin.y = visible.maxY - frame.height - 8 }
        panel.setFrameOrigin(frame.origin)
    }

    private func updateStatusItem(rebuildMenu: Bool = false) {
        guard let statusItem else { return }
        statusItem.isVisible = true
        guard let button = statusItem.button else { return }

        if rebuildMenu || statusItem.menu == nil {
            statusItem.menu = makeControlMenu()
        }

        let quota = usageView.quota
        let percent = quota?.remainingPercent
        let title = percent.map { "\(Int($0.rounded()))%" } ?? "—"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]

        button.image = makeStatusRingImage(percent: percent)
        button.imagePosition = .imageLeft
        button.imageScaling = .scaleProportionallyDown
        button.attributedTitle = NSAttributedString(string: title, attributes: titleAttributes)
        button.toolTip = quota.map { "Codex 额度重置还剩 \(PhraseEngine.coarseCountdown(to: $0.resetsAt))" }
            ?? usageView.errorText ?? "正在读取 Codex 周额度"
        button.setAccessibilityLabel(button.toolTip ?? "Codex 周额度")
    }

    private func makeStatusRingImage(percent: Double?) -> NSImage {
        let image = NSImage(size: NSSize(width: 15, height: 15), flipped: false) { _ in
            let rect = NSRect(x: 1.5, y: 1.5, width: 12, height: 12)
            let lineWidth: CGFloat = 1.7
            let track = NSBezierPath(ovalIn: rect)
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.18).setStroke()
            track.stroke()

            guard let percent else { return true }
            let displayedProgress = CGFloat(StatusRingGeometry.displayedProgress(
                for: percent,
                diameter: Double(rect.width)
            ))
            guard displayedProgress > 0 else { return true }

            let color: NSColor = percent <= 5 ? .systemRed : percent <= 20 ? .systemOrange : .white
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: rect.width / 2,
                startAngle: 90,
                endAngle: 90 - 360 * displayedProgress,
                clockwise: true
            )
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .butt
            color.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    func usageViewDidRequestRefresh() {
        refreshNow()
    }

    func usageViewDidRequestContextMenu(event: NSEvent, view: NSView) {
        NSMenu.popUpContextMenu(makeControlMenu(), with: event, for: view)
    }

    private func makeControlMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("打开设置…", #selector(openSettings)))
        menu.addItem(menuItem("立即刷新", #selector(refreshAction)))
        let desktopCard = menuItem("显示桌面卡片", #selector(toggleDesktopCard))
        desktopCard.state = preferences.showDesktopCard ? .on : .off
        menu.addItem(desktopCard)

        let themeRoot = NSMenuItem(title: "切换皮肤", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for theme in ThemeStore.shared.themes {
            let item = NSMenuItem(title: theme.name, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.id
            item.state = preferences.themeID == theme.id ? .on : .off
            themeMenu.addItem(item)
        }
        menu.setSubmenu(themeMenu, for: themeRoot)
        menu.addItem(themeRoot)

        let modeRoot = NSMenuItem(title: "卡片形态", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in DisplayMode.desktopModes {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = preferences.displayMode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        menu.setSubmenu(modeMenu, for: modeRoot)
        menu.addItem(modeRoot)

        let top = menuItem("始终置顶", #selector(toggleAlwaysOnTop))
        top.state = preferences.alwaysOnTop ? .on : .off
        menu.addItem(top)

        let login = menuItem("开机自动启动", #selector(toggleLaunchAtLogin))
        login.state = isLaunchAtLoginConfigured ? .on : .off
        menu.addItem(login)
        menu.addItem(menuItem("移回桌面右下角", #selector(resetPosition)))
        menu.addItem(.separator())
        menu.addItem(menuItem("检查更新…", #selector(checkUpdateAction)))
        menu.addItem(menuItem("关于 Codex Usage Strip…", #selector(showAboutAction)))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 Codex Usage Strip", #selector(quit)))
        return menu
    }

    func usageViewDidEndResize() {
        snapToNearestEdge()
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private var isLaunchAtLoginConfigured: Bool {
        LaunchAtLoginManager.shared.isEnabled
    }

    @objc private func openSettings() { settingsController?.present() }
    @objc private func tickTimerFired() {
        usageView.now = Date()
        updateStatusItem()
    }
    @objc private func refreshTimerFired() { refreshNow() }
    @objc private func refreshAction() { refreshNow() }
    @objc private func resetPosition() { moveToBottomRight() }
    @objc private func checkUpdateAction() { checkForUpdates(manual: true) }
    @objc private func showAboutAction() { aboutController?.present() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        preferences.themeID = id
        applyPreferences(rescheduleRefresh: false)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = DisplayMode(rawValue: raw) else { return }
        preferences.displayMode = mode
        applyPreferences(rescheduleRefresh: false)
    }

    @objc private func toggleAlwaysOnTop() {
        preferences.alwaysOnTop.toggle()
        applyPreferences(rescheduleRefresh: false)
    }

    @objc private func toggleDesktopCard() {
        preferences.showDesktopCard.toggle()
        applyPreferences(rescheduleRefresh: false)
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginConfigured)
    }

    private func showAlert(title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
