import Foundation

enum QuotaError: LocalizedError {
    case codexNotFound
    case noWeeklyWindow
    case timedOut
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "找不到本机 Codex"
        case .noWeeklyWindow: return "当前账户暂无每周额度"
        case .timedOut: return "读取超时，稍后自动重试"
        case .malformedResponse: return "Codex 返回了无法识别的数据"
        }
    }
}

final class CodexQuotaService {
    private var process: Process?
    private var stdin: FileHandle?
    private var isRefreshing = false
    private var nextRequestID = 1
    private var pending: [Int: (Result<WeeklyQuota, Error>) -> Void] = [:]
    private var buffer = Data()
    private let queue = DispatchQueue(label: "app.codexusagestrip.codex-service")

    func refresh(completion: @escaping (Result<WeeklyQuota, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.isRefreshing { return }
            self.isRefreshing = true
            do {
                try self.ensureServer()
                let id = self.nextRequestID
                self.nextRequestID += 1
                self.pending[id] = completion
                try self.send(["method": "account/rateLimits/read", "id": id])
                self.queue.asyncAfter(deadline: .now() + 12) { [weak self] in
                    guard let self, let callback = self.pending.removeValue(forKey: id) else { return }
                    self.isRefreshing = false
                    DispatchQueue.main.async { callback(.failure(QuotaError.timedOut)) }
                }
            } catch {
                self.isRefreshing = false
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func stop() {
        queue.sync {
            process?.terminate()
            process = nil
            stdin = nil
            pending.removeAll()
            buffer.removeAll()
        }
    }

    private func ensureServer() throws {
        if let process, process.isRunning { return }
        guard let codexPath = Self.resolveCodexPath() else { throw QuotaError.codexNotFound }

        let newProcess = Process()
        let stdout = Pipe()
        let input = Pipe()
        newProcess.executableURL = URL(fileURLWithPath: codexPath)
        newProcess.arguments = ["app-server", "--stdio"]
        newProcess.standardOutput = stdout
        newProcess.standardInput = input
        newProcess.standardError = FileHandle.nullDevice

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { self?.consume(data) }
        }

        newProcess.terminationHandler = { [weak self] _ in
            self?.queue.async {
                self?.process = nil
                self?.stdin = nil
            }
        }

        try newProcess.run()
        process = newProcess
        stdin = input.fileHandleForWriting
        try send([
            "method": "initialize",
            "id": 0,
            "params": [
                "clientInfo": [
                    "name": "codex_usage_strip",
                    "title": "Codex Usage Strip",
                    "version": AppInfo.version
                ]
            ]
        ])
        try send(["method": "initialized", "params": [:] as [String: Any]])
    }

    private func send(_ object: [String: Any]) throws {
        guard let stdin else { throw QuotaError.codexNotFound }
        let data = try JSONSerialization.data(withJSONObject: object)
        stdin.write(data)
        stdin.write(Data([0x0A]))
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                continue
            }
            if let id = (object["id"] as? NSNumber)?.intValue,
               id > 0,
               let callback = pending.removeValue(forKey: id) {
                isRefreshing = false
                let result: Result<WeeklyQuota, Error>
                if let quota = Self.parseWeeklyQuota(from: object) {
                    result = .success(quota)
                } else {
                    result = .failure(QuotaError.noWeeklyWindow)
                }
                DispatchQueue.main.async { callback(result) }
            }
        }
    }

    static func resolveCodexPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory(),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        // App bundle layouts are compatibility fallbacks, not stable public paths.
        let bundledCandidates = ["/Applications", "\(home)/Applications"].flatMap { directory in
            ["ChatGPT.app", "Codex.app"].flatMap { app in
                [
                    "\(directory)/\(app)/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                    "\(directory)/\(app)/Contents/Resources/codex",
                    "\(directory)/\(app)/Contents/Resources/codex-cli/bin/codex"
                ]
            }
        }
        let cliCandidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex"
        ]
        let pathCandidates = (environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }
            .map { "\($0)/codex" }
        let candidates = [environment["CODEX_PATH"]].compactMap { $0 }
            + bundledCandidates + cliCandidates + pathCandidates
        return candidates.first { !$0.isEmpty && isExecutable($0) }
    }

    static func parseWeeklyQuota(from object: [String: Any]) -> WeeklyQuota? {
        guard let result = object["result"] as? [String: Any] else { return nil }

        let direct = result["rateLimits"] as? [String: Any]
        let directID = direct?["limitId"] as? String
        let totalLimit: [String: Any]?
        if let direct, directID == nil || directID == "codex" {
            totalLimit = direct
        } else if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            totalLimit = byID["codex"] as? [String: Any]
        } else {
            totalLimit = nil
        }

        guard let totalLimit else { return nil }
        let windows = ["primary", "secondary"].compactMap { totalLimit[$0] as? [String: Any] }
        guard let weekly = windows
            .filter({ (($0["windowDurationMins"] as? NSNumber)?.doubleValue ?? 0) >= 10_000 })
            .max(by: {
                (($0["windowDurationMins"] as? NSNumber)?.doubleValue ?? 0) <
                    (($1["windowDurationMins"] as? NSNumber)?.doubleValue ?? 0)
            }),
            let used = (weekly["usedPercent"] as? NSNumber)?.doubleValue,
            let resetTimestamp = (weekly["resetsAt"] as? NSNumber)?.doubleValue,
            let duration = (weekly["windowDurationMins"] as? NSNumber)?.doubleValue else {
            return nil
        }

        return WeeklyQuota(
            usedPercent: min(max(used, 0), 100),
            resetsAt: Date(timeIntervalSince1970: resetTimestamp),
            windowDurationMins: duration,
            updatedAt: Date()
        )
    }
}
