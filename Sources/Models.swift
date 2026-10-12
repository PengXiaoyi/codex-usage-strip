import AppKit
import Foundation

enum DisplayMode: String, CaseIterable, Codable {
    case pill
    case strip
    case card
    case minimalNumber
    case minimalLine
    case minimalCard
    case squareCircular
    case statusBar

    static var desktopModes: [DisplayMode] { allCases.filter { $0 != .statusBar } }

    var title: String {
        switch self {
        case .pill: return "胶囊"
        case .strip: return "横条"
        case .card: return "卡片"
        case .minimalNumber: return "极简数字"
        case .minimalLine: return "极简细线"
        case .minimalCard: return "极简卡片"
        case .squareCircular: return "方形圆环"
        case .statusBar: return "顶部状态栏"
        }
    }

    var size: NSSize {
        switch self {
        case .pill: return NSSize(width: 286, height: 48)
        case .strip: return NSSize(width: 340, height: 82)
        case .card: return NSSize(width: 340, height: 124)
        case .minimalNumber: return NSSize(width: 218, height: 44)
        case .minimalLine: return NSSize(width: 360, height: 40)
        case .minimalCard: return NSSize(width: 320, height: 86)
        case .squareCircular: return NSSize(width: 132, height: 132)
        case .statusBar: return NSSize(width: 340, height: 82)
        }
    }

    var minimumSize: NSSize {
        NSSize(width: size.width * 0.75, height: size.height * 0.75)
    }

    var maximumSize: NSSize {
        NSSize(width: size.width * 3, height: size.height * 3)
    }
}

enum ResizeCorner: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

enum ResizeGeometry {
    static func oppositeAnchor(for corner: ResizeCorner, frame: NSRect) -> NSPoint {
        switch corner {
        case .topLeft: return NSPoint(x: frame.maxX, y: frame.minY)
        case .topRight: return NSPoint(x: frame.minX, y: frame.minY)
        case .bottomLeft: return NSPoint(x: frame.maxX, y: frame.maxY)
        case .bottomRight: return NSPoint(x: frame.minX, y: frame.maxY)
        }
    }

    static func desiredSize(pointer: NSPoint, anchor: NSPoint, corner: ResizeCorner) -> NSSize {
        switch corner {
        case .topLeft:
            return NSSize(width: anchor.x - pointer.x, height: pointer.y - anchor.y)
        case .topRight:
            return NSSize(width: pointer.x - anchor.x, height: pointer.y - anchor.y)
        case .bottomLeft:
            return NSSize(width: anchor.x - pointer.x, height: anchor.y - pointer.y)
        case .bottomRight:
            return NSSize(width: pointer.x - anchor.x, height: anchor.y - pointer.y)
        }
    }

    static func frame(size: NSSize, anchor: NSPoint, corner: ResizeCorner) -> NSRect {
        switch corner {
        case .topLeft:
            return NSRect(x: anchor.x - size.width, y: anchor.y, width: size.width, height: size.height)
        case .topRight:
            return NSRect(x: anchor.x, y: anchor.y, width: size.width, height: size.height)
        case .bottomLeft:
            return NSRect(x: anchor.x - size.width, y: anchor.y - size.height, width: size.width, height: size.height)
        case .bottomRight:
            return NSRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
        }
    }
}

enum BackgroundImageMode: String, CaseIterable, Codable {
    case fill
    case fit
    case stretch
    case center
    case tile

    var title: String {
        switch self {
        case .fill: return "填充"
        case .fit: return "适应"
        case .stretch: return "拉伸"
        case .center: return "居中"
        case .tile: return "平铺"
        }
    }
}

enum PaceState: String, CaseIterable {
    case ample
    case steady
    case fast
    case critical

    var title: String {
        switch self {
        case .ample: return "宽裕"
        case .steady: return "正常"
        case .fast: return "偏快"
        case .critical: return "危险"
        }
    }
}

struct WeeklyQuota {
    let usedPercent: Double
    let resetsAt: Date
    let windowDurationMins: Double
    let updatedAt: Date

    var remainingPercent: Double {
        min(max(100 - usedPercent, 0), 100)
    }

    func paceState(now: Date = Date(), criticalThreshold: Double) -> PaceState {
        if remainingPercent <= criticalThreshold { return .critical }
        let windowSeconds = max(windowDurationMins * 60, 1)
        let timeRemainingPercent = min(max(resetsAt.timeIntervalSince(now) / windowSeconds * 100, 0), 100)
        let delta = remainingPercent - timeRemainingPercent
        if delta >= 15 { return .ample }
        if delta >= -10 { return .steady }
        return .fast
    }
}

struct PhraseSet: Codable, Equatable {
    var ample: String
    var steady: String
    var fast: String
    var critical: String

    static let standard = PhraseSet(
        ample: "额度充足，适合开启大任务",
        steady: "节奏正常，按计划推进",
        fast: "本周消耗偏快，先做关键任务",
        critical: "额度不多了，建议留给关键任务"
    )

    static let gentle = PhraseSet(
        ample: "状态很好，放心往前走",
        steady: "稳稳地用，时间和额度都刚好",
        fast: "稍微慢一点，把力气留给重点",
        critical: "先歇一歇，{countdown} 后又是新一周"
    )

    static let playful = PhraseSet(
        ample: "弹药充足，开大！",
        steady: "续航正常，保持航向",
        fast: "燃料掉得有点快，切到省电模式",
        critical: "红色警报：仅剩 {remaining}%"
    )

    static let strict = PhraseSet(
        ample: "余量 {remaining}%，可执行高消耗任务",
        steady: "消耗符合周进度",
        fast: "消耗超过时间进度，降低非必要调用",
        critical: "余量低于阈值，暂停低优先级任务"
    )
}

final class AppPreferences {
    static let shared = AppPreferences()
    private let defaults = UserDefaults.standard

    var themeID: String {
        get { defaults.string(forKey: "themeID") ?? "graphite" }
        set { defaults.set(newValue, forKey: "themeID") }
    }

    var displayMode: DisplayMode {
        get { DisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "strip") ?? .strip }
        set { defaults.set(newValue.rawValue, forKey: "displayMode") }
    }

    var showDesktopCard: Bool {
        get { defaults.object(forKey: "showDesktopCard") == nil ? true : defaults.bool(forKey: "showDesktopCard") }
        set { defaults.set(newValue, forKey: "showDesktopCard") }
    }

    var alwaysOnTop: Bool {
        get { defaults.object(forKey: "alwaysOnTop") == nil ? true : defaults.bool(forKey: "alwaysOnTop") }
        set { defaults.set(newValue, forKey: "alwaysOnTop") }
    }

    var refreshInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: "refreshInterval")
            return value >= 30 ? value : 120
        }
        set { defaults.set(newValue, forKey: "refreshInterval") }
    }

    var criticalThreshold: Double {
        get {
            let value = defaults.double(forKey: "criticalThreshold")
            return value > 0 ? value : 10
        }
        set { defaults.set(newValue, forKey: "criticalThreshold") }
    }

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: "notificationsEnabled") }
        set { defaults.set(newValue, forKey: "notificationsEnabled") }
    }

    var backgroundImagePath: String? {
        get { defaults.string(forKey: "backgroundImagePath") }
        set {
            if let newValue { defaults.set(newValue, forKey: "backgroundImagePath") }
            else { defaults.removeObject(forKey: "backgroundImagePath") }
        }
    }

    var backgroundImageOpacity: Double {
        get {
            guard defaults.object(forKey: "backgroundImageOpacity") != nil else { return 0.55 }
            return min(max(defaults.double(forKey: "backgroundImageOpacity"), 0), 1)
        }
        set { defaults.set(min(max(newValue, 0), 1), forKey: "backgroundImageOpacity") }
    }

    var overallOpacity: Double {
        get {
            guard defaults.object(forKey: "overallOpacity") != nil else { return 1 }
            return min(max(defaults.double(forKey: "overallOpacity"), 0.2), 1)
        }
        set { defaults.set(min(max(newValue, 0.2), 1), forKey: "overallOpacity") }
    }

    var backgroundImageMode: BackgroundImageMode {
        get { BackgroundImageMode(rawValue: defaults.string(forKey: "backgroundImageMode") ?? "fill") ?? .fill }
        set { defaults.set(newValue.rawValue, forKey: "backgroundImageMode") }
    }

    var phraseSet: PhraseSet {
        get {
            guard let data = defaults.data(forKey: "phraseSet"),
                  let value = try? JSONDecoder().decode(PhraseSet.self, from: data) else {
                return .standard
            }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "phraseSet")
            }
        }
    }

    var launchAtLoginConfigured: Bool {
        get { defaults.bool(forKey: "launchAtLoginConfigured") }
        set { defaults.set(newValue, forKey: "launchAtLoginConfigured") }
    }

    var automaticUpdateChecks: Bool {
        get { defaults.object(forKey: "automaticUpdateChecks") == nil ? true : defaults.bool(forKey: "automaticUpdateChecks") }
        set { defaults.set(newValue, forKey: "automaticUpdateChecks") }
    }

    func windowSize(for mode: DisplayMode) -> NSSize? {
        guard let value = defaults.string(forKey: "windowSize.\(mode.rawValue)") else { return nil }
        let parts = value.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return NSSize(width: parts[0], height: parts[1])
    }

    func setWindowSize(_ size: NSSize, for mode: DisplayMode) {
        defaults.set("\(size.width),\(size.height)", forKey: "windowSize.\(mode.rawValue)")
    }

    func clearWindowSize(for mode: DisplayMode) {
        defaults.removeObject(forKey: "windowSize.\(mode.rawValue)")
    }

    private init() {
        LegacyMigration.migrateDefaults(to: defaults)
        if displayMode == .statusBar {
            if defaults.object(forKey: "showDesktopCard") == nil { showDesktopCard = false }
            displayMode = .strip
        }
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&number)
        let r, g, b, a: UInt64
        switch cleaned.count {
        case 8:
            r = number >> 24
            g = number >> 16 & 0xFF
            b = number >> 8 & 0xFF
            a = number & 0xFF
        default:
            r = number >> 16
            g = number >> 8 & 0xFF
            b = number & 0xFF
            a = 0xFF
        }
        self.init(
            calibratedRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
