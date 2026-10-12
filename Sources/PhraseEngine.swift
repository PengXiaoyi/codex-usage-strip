import Foundation

struct PhraseEngine {
    static func phrase(
        for quota: WeeklyQuota,
        state: PaceState,
        phrases: PhraseSet,
        now: Date = Date()
    ) -> String {
        let template: String
        switch state {
        case .ample: template = phrases.ample
        case .steady: template = phrases.steady
        case .fast: template = phrases.fast
        case .critical: template = phrases.critical
        }

        let replacements = [
            "{remaining}": "\(Int(quota.remainingPercent.rounded()))",
            "{used}": "\(Int(quota.usedPercent.rounded()))",
            "{countdown}": countdown(to: quota.resetsAt, now: now),
            "{resetTime}": resetTimeString(for: quota.resetsAt),
            "{pace}": state.title,
            "{updatedAt}": updateFormatter.string(from: quota.updatedAt)
        ]

        return replacements.reduce(template) { value, pair in
            value.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(Int(date.timeIntervalSince(now)), 0)
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 { return "\(days)天 \(String(format: "%02d", hours)):\(String(format: "%02d", minutes))" }
        if hours > 0 { return "\(hours)小时 \(String(format: "%02d", minutes))分" }
        return "\(max(minutes, 1))分钟"
    }

    static func coarseCountdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(Int(date.timeIntervalSince(now)), 0)
        guard seconds >= 3_600 else { return "不足1小时" }

        let totalHours = seconds / 3_600
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0 {
            return hours > 0 ? "\(days)天 \(hours)小时" : "\(days)天"
        }
        return "\(totalHours)小时"
    }

    static func resetTimeString(for date: Date) -> String {
        resetFormatter.string(from: date)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let updateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
