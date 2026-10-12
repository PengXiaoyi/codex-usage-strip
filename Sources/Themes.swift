import AppKit
import Foundation

enum ProgressStyle: String, Codable {
    case rounded
    case segmented
    case neon
    case hairline
}

struct ThemeDefinition: Codable, Equatable {
    let schemaVersion: Int
    let id: String
    let name: String
    let subtitle: String
    let backgroundTop: String
    let backgroundBottom: String
    let border: String
    let track: String
    let accent: String
    let warning: String
    let danger: String
    let primaryText: String
    let secondaryText: String
    let glow: String
    let cornerRadius: Double
    let progressStyle: ProgressStyle
    let fontName: String?
    let usesMonospacedDigits: Bool

    func accentColor(for state: PaceState) -> NSColor {
        switch state {
        case .critical: return NSColor(hex: danger)
        case .fast: return NSColor(hex: warning)
        case .ample, .steady: return NSColor(hex: accent)
        }
    }
}

final class ThemeStore {
    static let shared = ThemeStore()

    let builtIns: [ThemeDefinition] = [
        ThemeDefinition(
            schemaVersion: 1, id: "graphite", name: "Graphite", subtitle: "克制、安静、接近 ChatGPT",
            backgroundTop: "202124F2", backgroundBottom: "141518F2", border: "FFFFFF1F",
            track: "FFFFFF1C", accent: "68DDB1", warning: "FFB547", danger: "FF5D68",
            primaryText: "F7F7F5", secondaryText: "B9BBB8", glow: "68DDB142",
            cornerRadius: 18, progressStyle: .rounded, fontName: "Avenir Next", usesMonospacedDigits: true
        ),
        ThemeDefinition(
            schemaVersion: 1, id: "paper", name: "Paper", subtitle: "温暖纸面与朱砂标记",
            backgroundTop: "F5EEDFFF", backgroundBottom: "E9DDC8FF", border: "6F5D433D",
            track: "6F5D4326", accent: "C64B35", warning: "D1842E", danger: "A72F2B",
            primaryText: "3B3027", secondaryText: "746456", glow: "C64B352E",
            cornerRadius: 10, progressStyle: .hairline, fontName: "Songti SC", usesMonospacedDigits: false
        ),
        ThemeDefinition(
            schemaVersion: 1, id: "terminal", name: "Terminal", subtitle: "复古 CRT 终端仪表",
            backgroundTop: "07120DFA", backgroundBottom: "020806FA", border: "53FF9B59",
            track: "53FF9B1F", accent: "53FF9B", warning: "FFD75A", danger: "FF625F",
            primaryText: "B7FFD3", secondaryText: "70BF8D", glow: "53FF9B73",
            cornerRadius: 5, progressStyle: .segmented, fontName: "Menlo", usesMonospacedDigits: true
        ),
        ThemeDefinition(
            schemaVersion: 1, id: "traffic", name: "Traffic", subtitle: "一眼判断当前安全等级",
            backgroundTop: "17202AFF", backgroundBottom: "0D1218FF", border: "DCE5EF24",
            track: "FFFFFF20", accent: "53D769", warning: "FFCC33", danger: "FF453A",
            primaryText: "F4F7FA", secondaryText: "A9B3BD", glow: "53D76952",
            cornerRadius: 22, progressStyle: .segmented, fontName: "DIN Alternate", usesMonospacedDigits: true
        ),
        ThemeDefinition(
            schemaVersion: 1, id: "sakura", name: "Sakura", subtitle: "柔和但不甜腻的晨雾粉",
            backgroundTop: "FFF1F5F7", backgroundBottom: "EBDCEBFA", border: "A54F7B2B",
            track: "8C587128", accent: "D85C91", warning: "E68B4D", danger: "C83E55",
            primaryText: "542D42", secondaryText: "896276", glow: "D85C9140",
            cornerRadius: 24, progressStyle: .rounded, fontName: "Klee", usesMonospacedDigits: false
        ),
        ThemeDefinition(
            schemaVersion: 1, id: "cyber", name: "Cyber Meter", subtitle: "高对比霓虹能量槽",
            backgroundTop: "11102BFA", backgroundBottom: "050615FA", border: "48E7FF52",
            track: "6B62FF26", accent: "3FE9FF", warning: "FFCE47", danger: "FF3D8E",
            primaryText: "F5F2FF", secondaryText: "9E9AC5", glow: "3FE9FF8A",
            cornerRadius: 14, progressStyle: .neon, fontName: "Futura", usesMonospacedDigits: true
        ),
        ThemeDefinition(
            schemaVersion: 1, id: "system-light", name: "System Light", subtitle: "明亮、安静、接近 macOS 系统界面",
            backgroundTop: "FFFFFFE6", backgroundBottom: "F2F2F7E6", border: "00000010",
            track: "00000012", accent: "007AFF", warning: "FF9500", danger: "FF3B30",
            primaryText: "1D1D1F", secondaryText: "6E6E73", glow: "007AFF18",
            cornerRadius: 16, progressStyle: .rounded, fontName: nil, usesMonospacedDigits: true
        ),
        ThemeDefinition(
            schemaVersion: 1, id: "system-dark", name: "System Dark", subtitle: "深色材质与克制的系统蓝",
            backgroundTop: "2C2C2EE6", backgroundBottom: "1C1C1EE6", border: "FFFFFF14",
            track: "FFFFFF14", accent: "0A84FF", warning: "FF9F0A", danger: "FF453A",
            primaryText: "F5F5F7", secondaryText: "98989D", glow: "0A84FF24",
            cornerRadius: 16, progressStyle: .rounded, fontName: nil, usesMonospacedDigits: true
        ),
        ThemeDefinition(
            schemaVersion: 1, id: "system-blue", name: "System Blue", subtitle: "蓝色层次与轻量玻璃感",
            backgroundTop: "173A53E0", backgroundBottom: "0D2437E0", border: "64D2FF24",
            track: "FFFFFF14", accent: "0A84FF", warning: "FF9F0A", danger: "FF453A",
            primaryText: "F5F5F7", secondaryText: "B7CAD9", glow: "0A84FF24",
            cornerRadius: 16, progressStyle: .rounded, fontName: nil, usesMonospacedDigits: true
        ),
        ThemeDefinition(
            schemaVersion: 1, id: "square-light", name: "Square Light", subtitle: "方形容器、蓝色圆环与轻盈留白",
            backgroundTop: "F7F7F9E8", backgroundBottom: "EAEAEFE8", border: "00000012",
            track: "00000014", accent: "007AFF", warning: "FF9500", danger: "FF3B30",
            primaryText: "1D1D1F", secondaryText: "6E6E73", glow: "007AFF18",
            cornerRadius: 20, progressStyle: .rounded, fontName: nil, usesMonospacedDigits: true
        )
    ]

    var themes: [ThemeDefinition] {
        builtIns + customThemes()
    }

    func theme(id: String) -> ThemeDefinition {
        themes.first(where: { $0.id == id }) ?? builtIns[0]
    }

    func importTheme(from url: URL) throws -> ThemeDefinition {
        let data = try Data(contentsOf: url)
        let theme = try JSONDecoder().decode(ThemeDefinition.self, from: data)
        return try installTheme(theme)
    }

    func installTheme(_ theme: ThemeDefinition) throws -> ThemeDefinition {
        guard theme.schemaVersion == 1,
              !theme.id.isEmpty,
              !theme.name.isEmpty else {
            throw NSError(domain: "CodexUsageStrip.Theme", code: 1, userInfo: [NSLocalizedDescriptionKey: "主题文件格式不受支持"])
        }
        let destination = try themesDirectory().appendingPathComponent("\(sanitized(theme.id)).quotatheme")
        let encoded = try JSONEncoder.pretty.encode(theme)
        try encoded.write(to: destination, options: .atomic)
        return theme
    }

    func exportTheme(_ theme: ThemeDefinition, to url: URL) throws {
        try JSONEncoder.pretty.encode(theme).write(to: url, options: .atomic)
    }

    private func customThemes() -> [ThemeDefinition] {
        guard let directory = try? themesDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(ThemeDefinition.self, from: data)
        }
    }

    private func themesDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Codex Usage Strip/Themes", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func sanitized(_ value: String) -> String {
        value.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
    }

    private init() {}
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
