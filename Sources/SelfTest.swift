import Foundation

enum SelfTest {
    static func run() throws {
        try expect(ThemeStore.shared.builtIns.count == 10, "应有 10 套内置皮肤")
        try expect(Set(ThemeStore.shared.builtIns.map(\.id)).count == 10, "皮肤 ID 必须唯一")
        try expect(BackgroundImageMode.allCases.count == 5, "应有 5 种背景图片显示方式")
        try expect(AppInfo.version == "2.3.2" && AppInfo.build == "8", "应用版本信息不一致")
        let modernCodex = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        let legacyCodex = "/Applications/ChatGPT.app/Contents/Resources/codex"
        let userCodex = "/test/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        for executable in [modernCodex, legacyCodex, userCodex, "/opt/homebrew/bin/codex", "/custom/bin/codex"] {
            try expect(CodexQuotaService.resolveCodexPath(
                environment: ["CODEX_PATH": "/missing/codex", "PATH": "/custom/bin"],
                home: "/test",
                isExecutable: { $0 == executable }
            ) == executable, "未能检测 Codex 路径：\(executable)")
        }
        try expect(CodexQuotaService.resolveCodexPath(
            environment: ["CODEX_PATH": "/override/codex"], home: "/test",
            isExecutable: { $0 == "/override/codex" || $0 == modernCodex }
        ) == "/override/codex", "CODEX_PATH 应优先于自动检测")
        try expect(CodexQuotaService.resolveCodexPath(
            environment: ["PATH": ":relative/bin"], home: "/test", isExecutable: { _ in false }
        ) == nil, "无有效 Codex 安装时应返回空路径")
        let installedExecutable = "/Applications/Codex Usage Strip.app/Contents/MacOS/CodexUsageStrip"
        var loginAgent: [String: Any] = [
            "Label": "app.codexusagestrip.desktop",
            "ProgramArguments": ["/missing/development/CodexUsageStrip"],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        try expect(!LaunchAtLoginManager.fallbackMatches(loginAgent, executable: installedExecutable),
                   "失效开发版路径不能视为有效开机启动")
        loginAgent["ProgramArguments"] = [installedExecutable]
        let loginAgentData = try PropertyListSerialization.data(fromPropertyList: loginAgent, format: .xml, options: 0)
        let decodedAgent = try PropertyListSerialization.propertyList(from: loginAgentData, options: [], format: nil) as! [String: Any]
        try expect(LaunchAtLoginManager.fallbackMatches(decodedAgent, executable: installedExecutable),
                   "正式安装路径的开机启动配置无法往返")
        loginAgent["RunAtLoad"] = false
        try expect(!LaunchAtLoginManager.fallbackMatches(loginAgent, executable: installedExecutable),
                   "未启用登录时运行的配置不能视为有效开机启动")
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
        let phrase = PhraseEngine.phrase(
            for: quota,
            state: .critical,
            phrases: PhraseSet(ample: "", steady: "", fast: "", critical: "剩余 {remaining}% · {countdown}"),
            now: now
        )
        try expect(phrase.contains("28%") && phrase.contains("2天"), "话术变量替换失败")
        try expect(
            PhraseEngine.coarseCountdown(to: now.addingTimeInterval(2 * 86_400 + 3 * 3_600 + 59 * 60), now: now) == "2天 3小时"
                && PhraseEngine.coarseCountdown(to: now.addingTimeInterval(45 * 60), now: now) == "不足1小时",
            "粗粒度倒计时格式错误"
        )
        let completeRing = StatusRingGeometry.displayedProgress(for: 100, diameter: 12)
        let roundedCompleteRing = StatusRingGeometry.displayedProgress(for: 99.5, diameter: 12)
        let gappedRing = StatusRingGeometry.displayedProgress(for: 98, diameter: 12)
        try expect(
            completeRing == 1 && roundedCompleteRing == 1 && gappedRing < 0.98 && gappedRing > 0.94,
            "状态栏圆环缺口规则错误"
        )

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
                windowSizes: ["strip": PortableSize(DisplayMode.strip.size)],
                showDesktopCard: false
            ),
            selectedTheme: ThemeStore.shared.builtIns[0],
            background: nil
        )
        let configurationEncoder = JSONEncoder()
        configurationEncoder.dateEncodingStrategy = .iso8601
        let configurationData = try configurationEncoder.encode(portableConfiguration)
        let decodedConfiguration = try ConfigurationStore.decodeForValidation(configurationData)
        try expect(decodedConfiguration.preferences.themeID == "graphite", "配置导出格式无法往返")
        try expect(decodedConfiguration.preferences.showDesktopCard == false, "未保留卡片隐藏设置")
        var legacyObject = try JSONSerialization.jsonObject(with: configurationData) as! [String: Any]
        var legacyPreferences = legacyObject["preferences"] as! [String: Any]
        legacyPreferences.removeValue(forKey: "showDesktopCard")
        legacyPreferences["displayMode"] = "statusBar"
        legacyObject["preferences"] = legacyPreferences
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacyConfiguration = try ConfigurationStore.decodeForValidation(legacyData)
        try expect(legacyConfiguration.preferences.showDesktopCard == nil
            && legacyConfiguration.preferences.displayMode == .statusBar, "无法读取旧版状态栏配置")

        print("PASS themes=10")
        print("PASS version=2.3.2 build=8")
        print("PASS codex-path-detection")
        print("PASS launch-at-login-stale-path-validation")
        print("PASS background-modes=5")
        print("PASS four-corner-resize-bounds")
        print("PASS phrase-variables")
        print("PASS weekly-parser")
        print("PASS total-quota-only")
        print("PASS portable-configuration")
        print("PASS desktop-card-configuration-compatibility")
        print("PASS sparkle-default-disabled=\(!AppInfo.sparkleConfigurationReady)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw NSError(domain: "CodexUsageStrip.SelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
