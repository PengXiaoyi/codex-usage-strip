import AppKit
import Foundation

struct PortableSize: Codable, Equatable {
    let width: Double
    let height: Double

    init(_ size: NSSize) {
        width = size.width
        height = size.height
    }

    var nsSize: NSSize { NSSize(width: width, height: height) }
}

struct PortableBackground: Codable {
    let fileExtension: String
    let data: Data
}

struct PortablePreferences: Codable {
    let themeID: String
    let displayMode: DisplayMode
    let alwaysOnTop: Bool
    let refreshInterval: TimeInterval
    let criticalThreshold: Double
    let notificationsEnabled: Bool
    let backgroundImageOpacity: Double
    let overallOpacity: Double
    let backgroundImageMode: BackgroundImageMode
    let phraseSet: PhraseSet
    let automaticUpdateChecks: Bool
    let windowSizes: [String: PortableSize]
    var showDesktopWidget: Bool? = nil
}

struct CodexUsageStripConfiguration: Codable {
    let schemaVersion: Int
    let exportedByVersion: String
    let exportedAt: Date
    let preferences: PortablePreferences
    let selectedTheme: ThemeDefinition
    let background: PortableBackground?
}

enum ConfigurationStore {
    static let fileExtension = "codexusagestripconfig"
    static let legacyFileExtension = "quotaglowconfig"

    static func export(to url: URL, preferences: AppPreferences = .shared, themeStore: ThemeStore = .shared) throws {
        var windowSizes: [String: PortableSize] = [:]
        for mode in DisplayMode.allCases {
            if let size = preferences.windowSize(for: mode) {
                windowSizes[mode.rawValue] = PortableSize(size)
            }
        }

        let background: PortableBackground?
        if let path = preferences.backgroundImagePath {
            let source = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: source)
            background = PortableBackground(
                fileExtension: source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased(),
                data: data
            )
        } else {
            background = nil
        }

        let configuration = CodexUsageStripConfiguration(
            schemaVersion: 1,
            exportedByVersion: AppInfo.version,
            exportedAt: Date(),
            preferences: PortablePreferences(
                themeID: preferences.themeID,
                displayMode: preferences.displayMode,
                alwaysOnTop: preferences.alwaysOnTop,
                refreshInterval: preferences.refreshInterval,
                criticalThreshold: preferences.criticalThreshold,
                notificationsEnabled: preferences.notificationsEnabled,
                backgroundImageOpacity: preferences.backgroundImageOpacity,
                overallOpacity: preferences.overallOpacity,
                backgroundImageMode: preferences.backgroundImageMode,
                phraseSet: preferences.phraseSet,
                automaticUpdateChecks: preferences.automaticUpdateChecks,
                windowSizes: windowSizes,
                showDesktopWidget: preferences.showDesktopWidget
            ),
            selectedTheme: themeStore.theme(id: preferences.themeID),
            background: background
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }

    static func importConfiguration(
        from url: URL,
        preferences: AppPreferences = .shared,
        themeStore: ThemeStore = .shared
    ) throws {
        let data = try Data(contentsOf: url)
        guard data.count <= 30 * 1_024 * 1_024 else {
            throw configurationError("配置文件不能超过 30 MB")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configuration = try decoder.decode(CodexUsageStripConfiguration.self, from: data)
        try validate(configuration)

        let rollbackURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Codex-Usage-Strip-rollback-\(UUID().uuidString).\(fileExtension)")
        try export(to: rollbackURL, preferences: preferences, themeStore: themeStore)
        defer { try? FileManager.default.removeItem(at: rollbackURL) }
        do {
            try apply(configuration, preferences: preferences, themeStore: themeStore)
        } catch {
            if let rollbackData = try? Data(contentsOf: rollbackURL),
               let rollback = try? decodeForValidation(rollbackData) {
                try? apply(rollback, preferences: preferences, themeStore: themeStore)
            }
            throw error
        }
    }

    private static func apply(
        _ configuration: CodexUsageStripConfiguration,
        preferences: AppPreferences,
        themeStore: ThemeStore
    ) throws {

        if !themeStore.builtIns.contains(where: { $0.id == configuration.selectedTheme.id }) {
            _ = try themeStore.installTheme(configuration.selectedTheme)
        }

        if let background = configuration.background {
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("Codex-Usage-Strip-import-\(UUID().uuidString).\(background.fileExtension)")
            try background.data.write(to: temporary, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporary) }
            _ = try BackgroundAssetStore.importImage(from: temporary, preferences: preferences)
        } else {
            try BackgroundAssetStore.clear(preferences: preferences)
        }

        let imported = configuration.preferences
        preferences.themeID = imported.themeID
        preferences.displayMode = imported.displayMode
        preferences.alwaysOnTop = imported.alwaysOnTop
        if let showDesktopWidget = imported.showDesktopWidget {
            preferences.showDesktopWidget = showDesktopWidget
        }
        preferences.refreshInterval = imported.refreshInterval
        preferences.criticalThreshold = imported.criticalThreshold
        preferences.notificationsEnabled = imported.notificationsEnabled
        preferences.backgroundImageOpacity = imported.backgroundImageOpacity
        preferences.overallOpacity = imported.overallOpacity
        preferences.backgroundImageMode = imported.backgroundImageMode
        preferences.phraseSet = imported.phraseSet
        preferences.automaticUpdateChecks = imported.automaticUpdateChecks
        for mode in DisplayMode.allCases {
            if let size = imported.windowSizes[mode.rawValue] {
                preferences.setWindowSize(size.nsSize, for: mode)
            } else {
                preferences.clearWindowSize(for: mode)
            }
        }
    }

    static func decodeForValidation(_ data: Data) throws -> CodexUsageStripConfiguration {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let configuration = try decoder.decode(CodexUsageStripConfiguration.self, from: data)
        try validate(configuration)
        return configuration
    }

    private static func validate(_ configuration: CodexUsageStripConfiguration) throws {
        guard configuration.schemaVersion == 1 else {
            throw configurationError("不支持的配置版本：\(configuration.schemaVersion)")
        }
        let settings = configuration.preferences
        guard configuration.selectedTheme.id == settings.themeID else {
            throw configurationError("皮肤信息与配置不一致")
        }
        guard configuration.selectedTheme.schemaVersion == 1 else {
            throw configurationError("皮肤版本不受支持")
        }
        guard (30...3_600).contains(settings.refreshInterval),
              (1...50).contains(settings.criticalThreshold),
              (0...1).contains(settings.backgroundImageOpacity),
              (0.2...1).contains(settings.overallOpacity) else {
            throw configurationError("配置中的数值超出允许范围")
        }
        let phrases = [settings.phraseSet.ample, settings.phraseSet.steady, settings.phraseSet.fast, settings.phraseSet.critical]
        guard phrases.allSatisfy({ $0.count <= 500 }) else {
            throw configurationError("单条自定义话术不能超过 500 个字符")
        }
        for (rawMode, size) in settings.windowSizes {
            guard let mode = DisplayMode(rawValue: rawMode),
                  size.width >= mode.minimumSize.width,
                  size.height >= mode.minimumSize.height,
                  size.width <= mode.maximumSize.width,
                  size.height <= mode.maximumSize.height,
                  abs(size.height - size.width * mode.size.height / mode.size.width) <= 1.5 else {
                throw configurationError("窗口尺寸配置无效")
            }
        }
        if let background = configuration.background {
            let allowedExtensions = ["png", "jpg", "jpeg", "webp", "heic"]
            guard background.data.count <= 20 * 1_024 * 1_024,
                  allowedExtensions.contains(background.fileExtension.lowercased()),
                  let image = NSImage(data: background.data), image.isValid else {
                throw configurationError("背景图片无效或超过 20 MB")
            }
            let width = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
            let height = image.representations.map(\.pixelsHigh).max() ?? Int(image.size.height)
            guard width <= 8_192, height <= 8_192 else {
                throw configurationError("背景图片尺寸不能超过 8192 × 8192")
            }
        }
    }

    private static func configurationError(_ text: String) -> NSError {
        NSError(domain: "CodexUsageStrip.Configuration", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
