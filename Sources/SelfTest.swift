import Foundation

enum SelfTest {
    static func run() throws {
        let currentCodex = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        let legacyCodex = "/Applications/ChatGPT.app/Contents/Resources/codex"
        let customCodex = "/custom/bin/codex"
        let fallbackPaths = [
            legacyCodex,
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/test-home/.local/bin/codex"
        ]
        func resolve(_ available: Set<String>, override: String? = nil) -> String? {
            CodexQuotaService.resolveCodexPath(
                environment: override.map { ["CODEX_PATH": $0] } ?? [:],
                home: "/test-home",
                isExecutable: { available.contains($0) }
            )
        }
        try expect(resolve([currentCodex]) == currentCodex, "未识别新版 ChatGPT 内置 Codex")
        try expect(resolve([currentCodex, legacyCodex]) == currentCodex, "应优先使用新版 ChatGPT 路径")
        try expect(resolve([currentCodex, customCodex], override: customCodex) == customCodex,
                   "CODEX_PATH 应优先于内置路径")
        try expect(resolve([currentCodex], override: customCodex) == currentCodex,
                   "不可执行的 CODEX_PATH 应继续回退")
        for path in fallbackPaths {
            try expect(resolve([path]) == path, "旧路径或独立 CLI 回退失败")
        }
        try expect(resolve([]) == nil, "没有可执行 Codex 时应返回 nil")
        print("PASS codex-path-discovery")

        try expect(ThemeStore.shared.builtIns.count == 6, "应有 6 套内置皮肤")
        try expect(Set(ThemeStore.shared.builtIns.map(\.id)).count == 6, "皮肤 ID 必须唯一")
        try expect(BackgroundImageMode.allCases.count == 5, "应有 5 种背景图片显示方式")
        try expect(AppInfo.version == "2.3.0" && AppInfo.build == "6", "应用版本信息不一致")
        try expect(DisplayMode.allCases.allSatisfy {
            $0.minimumSize.width < $0.size.width && $0.maximumSize.width > $0.size.width
                && abs(($0.size.width / $0.size.height) - ($0.minimumSize.width / $0.minimumSize.height)) < 0.0001
        }, "缩放边界或宽高比配置错误")
        let startFrame = NSRect(x: 100, y: 200, width: 340, height: 82)
        let resizedSize = NSSize(width: 510, height: 123)
        try expect(ResizeCorner.allCases.allSatisfy { corner in
            let anchor = ResizeGeometry.oppositeAnchor(for: corner, frame: startFrame)
            let resized = ResizeGeometry.frame(size: resizedSize, anchor: anchor, corner: corner)
            return resized.size == resizedSize
                && ResizeGeometry.oppositeAnchor(for: corner, frame: resized) == anchor
        }, "四角缩放未固定对角锚点")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = WeeklyQuota(
            usedPercent: 72,
            resetsAt: now.addingTimeInterval(2 * 86_400),
            windowDurationMins: 10_080,
            updatedAt: now
        )
        try expect(MenuBarText.title(quota: quota, error: nil, now: now) == "28% · 2天0时", "菜单栏应显示余量与倒计时")
        try expect(MenuBarText.title(quota: nil, error: nil) == "Codex · …", "首次加载状态错误")
        try expect(MenuBarText.title(quota: nil, error: "offline") == "Codex · —", "读取失败状态错误")
        for (seconds, expected) in [(0, "待重置"), (-1, "待重置"), (59, "不足1分"),
                                    (60, "1分"), (3599, "59分"), (3600, "1时0分"),
                                    (86399, "23时59分"), (86400, "1天0时")] {
            try expect(MenuBarText.countdown(to: now.addingTimeInterval(Double(seconds)), now: now) == expected,
                       "菜单栏倒计时边界错误")
        }
        print("PASS menu-bar-states-and-countdown")
        let phrase = PhraseEngine.phrase(
            for: quota,
            state: .critical,
            phrases: PhraseSet(ample: "", steady: "", fast: "", critical: "剩余 {remaining}% · {countdown}"),
            now: now
        )
        try expect(phrase.contains("28%") && phrase.contains("2天"), "话术变量替换失败")

        let fixture: [String: Any] = [
            "result": [
                "rateLimits": [
                    "limitId": "codex",
                    "primary": ["usedPercent": 8, "windowDurationMins": 300, "resetsAt": 1_800_000_100],
                    "secondary": ["usedPercent": 37, "windowDurationMins": 10_080, "resetsAt": 1_800_500_000]
                ],
                "rateLimitsByLimitId": [
                    "codex_bengalfox": [
                        "limitId": "codex_bengalfox",
                        "primary": ["usedPercent": 0, "windowDurationMins": 10_080, "resetsAt": 1_800_600_000]
                    ]
                ]
            ]
        ]
        let parsed = CodexQuotaService.parseWeeklyQuota(from: fixture)
        try expect(parsed != nil, "无法解析每周额度")
        try expect(Int(parsed?.remainingPercent ?? -1) == 63, "剩余百分比计算错误")
        try expect(parsed?.windowDurationMins == 10_080, "未正确选择每周窗口")

        let totalFallback: [String: Any] = [
            "result": [
                "rateLimitsByLimitId": [
                    "codex": [
                        "limitId": "codex",
                        "primary": ["usedPercent": 41, "windowDurationMins": 10_080, "resetsAt": 1_800_700_000]
                    ],
                    "codex_bengalfox": [
                        "limitId": "codex_bengalfox",
                        "primary": ["usedPercent": 0, "windowDurationMins": 10_080, "resetsAt": 1_800_800_000]
                    ]
                ]
            ]
        ]
        try expect(Int(CodexQuotaService.parseWeeklyQuota(from: totalFallback)?.remainingPercent ?? -1) == 59,
                   "未固定读取 codex 总额度")

        let modelOnly: [String: Any] = [
            "result": [
                "rateLimitsByLimitId": [
                    "codex_bengalfox": [
                        "limitId": "codex_bengalfox",
                        "primary": ["usedPercent": 0, "windowDurationMins": 10_080, "resetsAt": 1_800_800_000]
                    ]
                ]
            ]
        ]
        try expect(CodexQuotaService.parseWeeklyQuota(from: modelOnly) == nil, "不应读取模型独立额度")

        let portableConfiguration = CodexUsageStripConfiguration(
            schemaVersion: 1,
            exportedByVersion: "2.1.0",
            exportedAt: now,
            preferences: PortablePreferences(
                themeID: "graphite",
                displayMode: .strip,
                alwaysOnTop: true,
                refreshInterval: 120,
                criticalThreshold: 10,
                notificationsEnabled: false,
                backgroundImageOpacity: 0.55,
                overallOpacity: 1,
                backgroundImageMode: .fill,
                phraseSet: .standard,
                automaticUpdateChecks: true,
                windowSizes: ["strip": PortableSize(DisplayMode.strip.size)]
            ),
            selectedTheme: ThemeStore.shared.builtIns[0],
            background: nil
        )
        let configurationEncoder = JSONEncoder()
        configurationEncoder.dateEncodingStrategy = .iso8601
        let configurationData = try configurationEncoder.encode(portableConfiguration)
        let decodedConfiguration = try ConfigurationStore.decodeForValidation(configurationData)
        try expect(decodedConfiguration.preferences.themeID == "graphite", "配置导出格式无法往返")
        try expect(decodedConfiguration.preferences.showDesktopWidget == nil, "旧配置应兼容缺失的桌面悬浮条开关")
        var portablePreferences = portableConfiguration.preferences
        portablePreferences.showDesktopWidget = false
        let preferencesData = try JSONEncoder().encode(portablePreferences)
        let decodedPreferences = try JSONDecoder().decode(PortablePreferences.self, from: preferencesData)
        try expect(decodedPreferences.showDesktopWidget == false, "桌面悬浮条开关无法往返")

        print("PASS themes=6")
        print("PASS version=2.3.0 build=6")
        print("PASS background-modes=5")
        print("PASS four-corner-resize-bounds")
        print("PASS phrase-variables")
        print("PASS weekly-parser")
        print("PASS total-quota-only")
        print("PASS portable-configuration")
        print("PASS sparkle-default-disabled=\(!AppInfo.sparkleConfigurationReady)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw NSError(domain: "CodexUsageStrip.SelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
