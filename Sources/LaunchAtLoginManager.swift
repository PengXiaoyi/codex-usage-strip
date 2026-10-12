import Foundation
import ServiceManagement

final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private static let label = "app.codexusagestrip.desktop"
    private let legacyLabel = "app.quotaglow.desktop"

    var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled:
            return true
        case .requiresApproval:
            return false
        default:
            return hasValidFallback
        }
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requires_approval"
        default:
            if hasValidFallback { return "enabled_fallback" }
            if FileManager.default.fileExists(atPath: fallbackPlist.path) { return "stale_fallback" }
            return SMAppService.mainApp.status == .notFound ? "not_found" : "not_registered"
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                if SMAppService.mainApp.status == .notRegistered || SMAppService.mainApp.status == .notFound {
                    try SMAppService.mainApp.register()
                }
            } catch {
                // Local ad-hoc builds can be rejected by SMAppService. The per-user
                // LaunchAgent below is the deterministic fallback for those builds.
            }
            if SMAppService.mainApp.status == .requiresApproval {
                throw NSError(domain: "CodexUsageStrip.LaunchAtLogin", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "请在系统设置 → 通用 → 登录项与扩展中允许 Codex Usage Strip 开机启动。"
                ])
            }
            if SMAppService.mainApp.status == .enabled {
                try removeFallbackLaunchAgent()
                try removeLegacyFallbackLaunchAgent()
                return
            }
            try writeFallbackLaunchAgent()
            try? removeLegacyFallbackLaunchAgent()
        } else {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
            try removeFallbackLaunchAgent()
            try? removeLegacyFallbackLaunchAgent()
        }
    }

    func repairRegistrationIfNeeded() throws {
        guard SMAppService.mainApp.status != .requiresApproval else { return }
        let hasFallback = FileManager.default.fileExists(atPath: fallbackPlist.path)
        let hasLegacy = FileManager.default.fileExists(atPath: legacyFallbackPlist.path)
        guard hasFallback || hasLegacy else { return }
        if SMAppService.mainApp.status == .enabled {
            try removeFallbackLaunchAgent()
        } else if !hasValidFallback {
            try writeFallbackLaunchAgent()
        }
        try removeLegacyFallbackLaunchAgent()
    }

    private var fallbackExecutable: String {
        // Testing a development copy must not move an installed app's login item
        // back into a temporary build directory.
        let installedApps = ["/Applications", "\(NSHomeDirectory())/Applications"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("Codex Usage Strip.app") }
        for app in installedApps {
            if let bundle = Bundle(url: app), bundle.bundleIdentifier == Self.label,
               let executable = bundle.executableURL,
               FileManager.default.isExecutableFile(atPath: executable.path) {
                return executable.path
            }
        }
        return Bundle.main.executableURL?.path
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/CodexUsageStrip").path
    }

    private var hasValidFallback: Bool {
        guard FileManager.default.isExecutableFile(atPath: fallbackExecutable),
              let data = try? Data(contentsOf: fallbackPlist),
              let payload = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return false }
        return Self.fallbackMatches(payload, executable: fallbackExecutable)
    }

    static func fallbackMatches(_ payload: [String: Any], executable: String) -> Bool {
        payload["Label"] as? String == label
            && payload["ProgramArguments"] as? [String] == [executable]
            && payload["RunAtLoad"] as? Bool == true
            && payload["KeepAlive"] as? Bool == false
    }

    private var fallbackPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    private var legacyFallbackPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(legacyLabel).plist")
    }

    private func writeFallbackLaunchAgent() throws {
        let executable = fallbackExecutable
        let payload: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        let directory = fallbackPlist.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fallbackPlist, options: .atomic)
    }

    private func removeFallbackLaunchAgent() throws {
        if FileManager.default.fileExists(atPath: fallbackPlist.path) {
            try FileManager.default.removeItem(at: fallbackPlist)
        }
    }

    private func removeLegacyFallbackLaunchAgent() throws {
        if FileManager.default.fileExists(atPath: legacyFallbackPlist.path) {
            try FileManager.default.removeItem(at: legacyFallbackPlist)
        }
    }

    private init() {}
}
