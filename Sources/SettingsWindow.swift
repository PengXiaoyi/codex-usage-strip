import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    var onPreferencesChanged: (() -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onShowAbout: (() -> Void)?
    var onAutomaticUpdateChecksChanged: ((Bool) -> Void)?

    private let preferences = AppPreferences.shared
    private let themeStore = ThemeStore.shared
    private let preview = UsageStripView(frame: NSRect(origin: .zero, size: DisplayMode.strip.size))
    private let themePopup = NSPopUpButton()
    private let themeDescription = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl(labels: DisplayMode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let desktopWidgetSwitch = NSSwitch()
    private let alwaysOnTopSwitch = NSSwitch()
    private let launchAtLoginSwitch = NSSwitch()
    private let notificationsSwitch = NSSwitch()
    private let refreshPopup = NSPopUpButton()
    private let backgroundName = NSTextField(labelWithString: "未选择图片")
    private let clearBackgroundButton = NSButton()
    private let backgroundModePopup = NSPopUpButton()
    private let backgroundOpacitySlider = NSSlider(value: 55, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let backgroundOpacityLabel = NSTextField(labelWithString: "55%")
    private let overallOpacitySlider = NSSlider(value: 100, minValue: 20, maxValue: 100, target: nil, action: nil)
    private let overallOpacityLabel = NSTextField(labelWithString: "100%")
    private let thresholdSlider = NSSlider(value: 10, minValue: 5, maxValue: 30, target: nil, action: nil)
    private let thresholdLabel = NSTextField(labelWithString: "10%")
    private let presetPopup = NSPopUpButton()
    private let ampleField = NSTextField()
    private let steadyField = NSTextField()
    private let fastField = NSTextField()
    private let criticalField = NSTextField()
    private let automaticUpdateSwitch = NSSwitch()
    private let updateFeedLabel = NSTextField(wrappingLabelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Usage Strip 设置"
        window.minSize = NSSize(width: 620, height: 680)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildUI()
        reloadFromPreferences()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        reloadFromPreferences()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        preview.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(preview)

        let title = NSTextField(labelWithString: "菜单栏余量，一眼可见")
        title.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        let subtitle = NSTextField(labelWithString: "所有数据仅通过本机 Codex 读取，不上传账户信息。")
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.setHuggingPriority(.required, for: .vertical)
        header.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(header)

        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.addTabViewItem(makeAppearanceTab())
        tabs.addTabViewItem(makePhrasesTab())
        tabs.addTabViewItem(makeMaintenanceTab())
        content.addSubview(tabs)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),

            preview.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            preview.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            preview.widthAnchor.constraint(equalToConstant: DisplayMode.strip.size.width),
            preview.heightAnchor.constraint(equalToConstant: DisplayMode.strip.size.height),

            tabs.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 18),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
    }

    private func makeAppearanceTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "appearance")
        item.label = "外观与行为"

        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        themeDescription.font = NSFont.systemFont(ofSize: 11)
        themeDescription.textColor = .secondaryLabelColor
        modeControl.target = self
        modeControl.action = #selector(modeChanged)

        desktopWidgetSwitch.target = self
        desktopWidgetSwitch.action = #selector(switchChanged)
        alwaysOnTopSwitch.target = self
        alwaysOnTopSwitch.action = #selector(switchChanged)
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchSwitchChanged)
        notificationsSwitch.target = self
        notificationsSwitch.action = #selector(switchChanged)

        refreshPopup.addItems(withTitles: ["30 秒", "1 分钟", "2 分钟", "5 分钟", "15 分钟"])
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshChanged)

        thresholdSlider.target = self
        thresholdSlider.action = #selector(thresholdChanged)
        thresholdLabel.alignment = .right
        thresholdLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        let importButton = NSButton(title: "导入皮肤…", target: self, action: #selector(importTheme))
        let exportButton = NSButton(title: "导出当前皮肤…", target: self, action: #selector(exportTheme))
        let themeButtons = NSStackView(views: [importButton, exportButton])
        themeButtons.orientation = .horizontal
        themeButtons.spacing = 10

        let themeControl = NSStackView(views: [themePopup, themeDescription])
        themeControl.orientation = .vertical
        themeControl.alignment = .leading
        themeControl.spacing = 5

        let chooseBackgroundButton = NSButton(title: "选择图片…", target: self, action: #selector(selectBackgroundImage))
        clearBackgroundButton.title = "移除"
        clearBackgroundButton.target = self
        clearBackgroundButton.action = #selector(clearBackgroundImage)
        backgroundName.font = NSFont.systemFont(ofSize: 11)
        backgroundName.textColor = .secondaryLabelColor
        backgroundName.lineBreakMode = .byTruncatingMiddle
        let backgroundButtons = NSStackView(views: [chooseBackgroundButton, clearBackgroundButton])
        backgroundButtons.orientation = .horizontal
        backgroundButtons.spacing = 8
        let backgroundControl = NSStackView(views: [backgroundButtons, backgroundName])
        backgroundControl.orientation = .vertical
        backgroundControl.alignment = .leading
        backgroundControl.spacing = 5

        backgroundModePopup.addItems(withTitles: BackgroundImageMode.allCases.map(\.title))
        backgroundModePopup.target = self
        backgroundModePopup.action = #selector(backgroundModeChanged)
        configurePercentSlider(backgroundOpacitySlider, label: backgroundOpacityLabel, action: #selector(backgroundOpacityChanged))
        configurePercentSlider(overallOpacitySlider, label: overallOpacityLabel, action: #selector(overallOpacityChanged))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 13
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.addArrangedSubview(row(label: "桌面悬浮条", control: desktopWidgetSwitch))
        stack.addArrangedSubview(row(label: "皮肤", control: themeControl))
        stack.addArrangedSubview(row(label: "背景图片", control: backgroundControl))
        stack.addArrangedSubview(row(label: "图片方式", control: backgroundModePopup))
        stack.addArrangedSubview(row(label: "背景透明度", control: percentControl(backgroundOpacitySlider, label: backgroundOpacityLabel)))
        stack.addArrangedSubview(row(label: "整体透明度", control: percentControl(overallOpacitySlider, label: overallOpacityLabel)))
        stack.addArrangedSubview(row(label: "显示形态", control: modeControl))
        stack.addArrangedSubview(row(label: "始终置顶", control: alwaysOnTopSwitch))
        stack.addArrangedSubview(row(label: "开机自动启动", control: launchAtLoginSwitch))
        stack.addArrangedSubview(row(label: "额度提醒", control: notificationsSwitch))
        stack.addArrangedSubview(row(label: "刷新频率", control: refreshPopup))

        let thresholdControls = NSStackView(views: [thresholdSlider, thresholdLabel])
        thresholdControls.orientation = .horizontal
        thresholdControls.spacing = 8
        thresholdSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        thresholdLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        stack.addArrangedSubview(row(label: "危险阈值", control: thresholdControls))
        stack.addArrangedSubview(indented(themeButtons))

        item.view = stack
        return item
    }

    private func configurePercentSlider(_ slider: NSSlider, label: NSTextField, action: Selector) {
        slider.target = self
        slider.action = action
        slider.numberOfTickMarks = 0
        label.alignment = .right
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    }

    private func percentControl(_ slider: NSSlider, label: NSTextField) -> NSView {
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        label.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let stack = NSStackView(views: [slider, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func makePhrasesTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "phrases")
        item.label = "自定义话术"

        presetPopup.addItems(withTitles: ["默认", "温柔", "游戏化", "严格"])
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        [ampleField, steadyField, fastField, criticalField].forEach {
            $0.delegate = self
            $0.target = self
            $0.action = #selector(phraseChanged)
            $0.maximumNumberOfLines = 1
        }

        let help = NSTextField(wrappingLabelWithString: "可用变量：{remaining}、{used}、{countdown}、{resetTime}、{pace}、{updatedAt}")
        help.font = NSFont.systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.addArrangedSubview(row(label: "话术预设", control: presetPopup))
        stack.addArrangedSubview(row(label: "额度宽裕", control: ampleField))
        stack.addArrangedSubview(row(label: "节奏正常", control: steadyField))
        stack.addArrangedSubview(row(label: "消耗偏快", control: fastField))
        stack.addArrangedSubview(row(label: "额度危险", control: criticalField))
        stack.addArrangedSubview(indented(help))
        item.view = stack
        return item
    }

    private func makeMaintenanceTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "maintenance")
        item.label = "版本与迁移"

        let version = NSTextField(labelWithString: AppInfo.displayVersion)
        version.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        automaticUpdateSwitch.target = self
        automaticUpdateSwitch.action = #selector(automaticUpdateChanged)

        updateFeedLabel.font = NSFont.systemFont(ofSize: 11)
        updateFeedLabel.textColor = .secondaryLabelColor
        updateFeedLabel.maximumNumberOfLines = 3

        let exportButton = NSButton(title: "导出完整配置…", target: self, action: #selector(exportConfiguration))
        let importButton = NSButton(title: "导入配置…", target: self, action: #selector(importConfiguration))
        let configurationButtons = NSStackView(views: [exportButton, importButton])
        configurationButtons.orientation = .horizontal
        configurationButtons.spacing = 10

        let aboutButton = NSButton(title: "关于 Codex Usage Strip…", target: self, action: #selector(showAbout))
        let note = NSTextField(wrappingLabelWithString: "配置文件包含皮肤、话术、背景图片、透明度、刷新频率和各形态尺寸；开机启动状态不会跨设备导入。")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 4

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 18, bottom: 18, right: 18)
        stack.addArrangedSubview(row(label: "当前版本", control: version))
        stack.addArrangedSubview(row(label: "自动检查更新", control: automaticUpdateSwitch))
        stack.addArrangedSubview(indented(updateFeedLabel))
        stack.addArrangedSubview(row(label: "配置迁移", control: configurationButtons))
        stack.addArrangedSubview(indented(note))
        stack.addArrangedSubview(row(label: "产品信息", control: aboutButton))
        item.view = stack
        return item
    }

    private func row(label: String, control: NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        labelView.widthAnchor.constraint(equalToConstant: 112).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.setHuggingPriority(.required, for: .vertical)
        return row
    }

    private func indented(_ view: NSView) -> NSView {
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 126).isActive = true
        let row = NSStackView(views: [spacer, view])
        row.orientation = .horizontal
        row.setHuggingPriority(.required, for: .vertical)
        return row
    }

    private func reloadFromPreferences() {
        let themes = themeStore.themes
        themePopup.removeAllItems()
        themePopup.addItems(withTitles: themes.map(\.name))
        if let index = themes.firstIndex(where: { $0.id == preferences.themeID }) {
            themePopup.selectItem(at: index)
        }
        updateThemeDescription()
        modeControl.selectedSegment = DisplayMode.allCases.firstIndex(of: preferences.displayMode) ?? 1
        desktopWidgetSwitch.state = preferences.showDesktopWidget ? .on : .off
        alwaysOnTopSwitch.state = preferences.alwaysOnTop ? .on : .off
        launchAtLoginSwitch.state = isLaunchAtLoginConfigured ? .on : .off
        notificationsSwitch.state = preferences.notificationsEnabled ? .on : .off
        if let path = preferences.backgroundImagePath {
            backgroundName.stringValue = URL(fileURLWithPath: path).lastPathComponent
        } else {
            backgroundName.stringValue = "未选择图片"
        }
        clearBackgroundButton.isEnabled = preferences.backgroundImagePath != nil
        backgroundModePopup.selectItem(at: BackgroundImageMode.allCases.firstIndex(of: preferences.backgroundImageMode) ?? 0)
        backgroundOpacitySlider.doubleValue = preferences.backgroundImageOpacity * 100
        backgroundOpacityLabel.stringValue = "\(Int((preferences.backgroundImageOpacity * 100).rounded()))%"
        overallOpacitySlider.doubleValue = preferences.overallOpacity * 100
        overallOpacityLabel.stringValue = "\(Int((preferences.overallOpacity * 100).rounded()))%"
        let intervals: [TimeInterval] = [30, 60, 120, 300, 900]
        refreshPopup.selectItem(at: intervals.firstIndex(of: preferences.refreshInterval) ?? 2)
        thresholdSlider.doubleValue = preferences.criticalThreshold
        thresholdLabel.stringValue = "\(Int(preferences.criticalThreshold))%"
        automaticUpdateSwitch.state = preferences.automaticUpdateChecks ? .on : .off
        updateFeedLabel.stringValue = AppInfo.sparkleConfigurationReady
            ? "已启用 Sparkle 安全更新：自动校验、下载并安装新版本。"
            : "当前为本地发布通道；建立 GitHub Release 后注入更新源与公钥即可启用。"
        fillPhraseFields(preferences.phraseSet)
        updatePreview()
    }

    private func updatePreview() {
        let now = Date()
        preview.theme = themeStore.theme(id: preferences.themeID)
        preview.displayMode = .strip
        preview.phrases = preferences.phraseSet
        preview.criticalThreshold = preferences.criticalThreshold
        preview.backgroundImage = BackgroundAssetStore.currentImage(preferences: preferences)
        preview.backgroundImageOpacity = preferences.backgroundImageOpacity
        preview.backgroundImageMode = preferences.backgroundImageMode
        preview.alphaValue = CGFloat(preferences.overallOpacity)
        preview.quota = WeeklyQuota(
            usedPercent: 28,
            resetsAt: now.addingTimeInterval(4 * 86_400 + 8 * 3_600),
            windowDurationMins: 10_080,
            updatedAt: now
        )
        preview.now = now
    }

    private func updateThemeDescription() {
        let themes = themeStore.themes
        guard themePopup.indexOfSelectedItem >= 0, themePopup.indexOfSelectedItem < themes.count else { return }
        themeDescription.stringValue = themes[themePopup.indexOfSelectedItem].subtitle
    }

    private func fillPhraseFields(_ set: PhraseSet) {
        ampleField.stringValue = set.ample
        steadyField.stringValue = set.steady
        fastField.stringValue = set.fast
        criticalField.stringValue = set.critical
    }

    private var isLaunchAtLoginConfigured: Bool {
        LaunchAtLoginManager.shared.isEnabled
    }

    @objc private func themeChanged() {
        let themes = themeStore.themes
        guard themePopup.indexOfSelectedItem >= 0, themePopup.indexOfSelectedItem < themes.count else { return }
        preferences.themeID = themes[themePopup.indexOfSelectedItem].id
        updateThemeDescription()
        updatePreview()
        onPreferencesChanged?()
    }

    @objc private func modeChanged() {
        guard modeControl.selectedSegment >= 0 else { return }
        preferences.displayMode = DisplayMode.allCases[modeControl.selectedSegment]
        onPreferencesChanged?()
    }

    @objc private func switchChanged() {
        preferences.showDesktopWidget = desktopWidgetSwitch.state == .on
        preferences.alwaysOnTop = alwaysOnTopSwitch.state == .on
        preferences.notificationsEnabled = notificationsSwitch.state == .on
        onPreferencesChanged?()
    }

    @objc private func launchSwitchChanged() {
        onLaunchAtLoginChanged?(launchAtLoginSwitch.state == .on)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.launchAtLoginSwitch.state = self?.isLaunchAtLoginConfigured == true ? .on : .off
        }
    }

    @objc private func refreshChanged() {
        let intervals: [TimeInterval] = [30, 60, 120, 300, 900]
        preferences.refreshInterval = intervals[max(refreshPopup.indexOfSelectedItem, 0)]
        onPreferencesChanged?()
    }

    @objc private func selectBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .heic]
        panel.allowsMultipleSelection = false
        panel.message = "选择一张本地图片作为悬浮框背景"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try BackgroundAssetStore.importImage(from: url, preferences: preferences)
            reloadFromPreferences()
            onPreferencesChanged?()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func clearBackgroundImage() {
        do {
            try BackgroundAssetStore.clear(preferences: preferences)
            reloadFromPreferences()
            onPreferencesChanged?()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func backgroundModeChanged() {
        guard backgroundModePopup.indexOfSelectedItem >= 0 else { return }
        preferences.backgroundImageMode = BackgroundImageMode.allCases[backgroundModePopup.indexOfSelectedItem]
        updatePreview()
        onPreferencesChanged?()
    }

    @objc private func backgroundOpacityChanged() {
        let value = (backgroundOpacitySlider.doubleValue / 5).rounded() * 5
        backgroundOpacitySlider.doubleValue = value
        preferences.backgroundImageOpacity = value / 100
        backgroundOpacityLabel.stringValue = "\(Int(value))%"
        updatePreview()
        onPreferencesChanged?()
    }

    @objc private func overallOpacityChanged() {
        let value = (overallOpacitySlider.doubleValue / 5).rounded() * 5
        overallOpacitySlider.doubleValue = value
        preferences.overallOpacity = value / 100
        overallOpacityLabel.stringValue = "\(Int(value))%"
        updatePreview()
        onPreferencesChanged?()
    }

    @objc private func thresholdChanged() {
        let rounded = (thresholdSlider.doubleValue / 5).rounded() * 5
        thresholdSlider.doubleValue = rounded
        thresholdLabel.stringValue = "\(Int(rounded))%"
        preferences.criticalThreshold = rounded
        updatePreview()
        onPreferencesChanged?()
    }

    @objc private func presetChanged() {
        let set: PhraseSet
        switch presetPopup.indexOfSelectedItem {
        case 1: set = .gentle
        case 2: set = .playful
        case 3: set = .strict
        default: set = .standard
        }
        preferences.phraseSet = set
        fillPhraseFields(set)
        updatePreview()
        onPreferencesChanged?()
    }

    @objc private func phraseChanged() {
        let set = PhraseSet(
            ample: ampleField.stringValue,
            steady: steadyField.stringValue,
            fast: fastField.stringValue,
            critical: criticalField.stringValue
        )
        preferences.phraseSet = set
        updatePreview()
        onPreferencesChanged?()
    }

    func controlTextDidChange(_ obj: Notification) {
        phraseChanged()
    }

    @objc private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "quotatheme") ?? .json, .json]
        panel.allowsMultipleSelection = false
        panel.message = "选择 .quotatheme 或 JSON 主题文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let theme = try themeStore.importTheme(from: url)
            preferences.themeID = theme.id
            reloadFromPreferences()
            onPreferencesChanged?()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func exportTheme() {
        let theme = themeStore.theme(id: preferences.themeID)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(theme.id).quotatheme"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try themeStore.exportTheme(theme, to: url)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func automaticUpdateChanged() {
        let enabled = automaticUpdateSwitch.state == .on
        preferences.automaticUpdateChecks = enabled
        onAutomaticUpdateChecksChanged?(enabled)
    }

    @objc private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ConfigurationStore.fileExtension) ?? .json]
        panel.nameFieldStringValue = "Codex-Usage-Strip-configuration.\(ConfigurationStore.fileExtension)"
        panel.message = "导出可移植配置；开机启动状态不会写入文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigurationStore.export(to: url, preferences: preferences, themeStore: themeStore)
            showSuccess(title: "配置已导出", detail: url.lastPathComponent)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: ConfigurationStore.fileExtension) ?? .json,
            UTType(filenameExtension: ConfigurationStore.legacyFileExtension) ?? .json,
            .json
        ]
        panel.allowsMultipleSelection = false
        panel.message = "选择 Codex Usage Strip 配置文件；兼容旧版 .quotaglowconfig"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigurationStore.importConfiguration(from: url, preferences: preferences, themeStore: themeStore)
            reloadFromPreferences()
            onPreferencesChanged?()
            showSuccess(title: "配置已导入", detail: "外观、话术和窗口尺寸已经更新")
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func showAbout() {
        onShowAbout?()
    }

    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = text
        alert.runModal()
    }

    private func showSuccess(title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
