import Foundation

struct RateLimitsResponse: Decodable, Sendable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

struct RateLimitSnapshot: Decodable, Sendable {
    let limitId: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let planType: String?
}

struct RateLimitWindow: Decodable, Sendable {
    let usedPercent: Double?
    let windowDurationMins: Double?
    let resetsAt: TimeInterval?
}

struct UsageSummary: Sendable {
    let planType: String?
    let fiveHour: UsageWindow?
    let weekly: UsageWindow

    init(response: RateLimitsResponse) throws {
        let snapshot = response.rateLimitsByLimitId?["codex"]
            ?? response.rateLimits
            ?? response.rateLimitsByLimitId?.values.first

        guard let snapshot else {
            throw FetchError.invalidOutput
        }

        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }.map(UsageWindow.init)
        let fiveHour = windows.first { approximately($0.windowDurationMins, 300) }
        let weekly = windows.first { approximately($0.windowDurationMins, 10080) } ?? windows.first

        guard let weekly else {
            throw FetchError.invalidOutput
        }

        self.planType = snapshot.planType
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    var menuTitle: String {
        if let fiveHour {
            return "5h \(fiveHour.remainingPercent)% 7d \(weekly.remainingPercent)%"
        }
        return "7d \(weekly.remainingPercent)%"
    }

    var verboseTitle: String {
        if let fiveHour {
            return "Codex usage: 5-hour \(fiveHour.remainingPercent)% · weekly \(weekly.remainingPercent)%"
        }
        return "Codex usage: weekly \(weekly.remainingPercent)%"
    }

    func tooltip(formatter: DateFormatter) -> String {
        let weeklyReset = weekly.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        if let fiveHour {
            let fiveHourReset = fiveHour.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
            return "Codex usage\n5-hour remaining: \(fiveHour.remainingPercent)% · resets \(fiveHourReset)\nWeekly remaining: \(weekly.remainingPercent)% · resets \(weeklyReset)"
        }
        return "Codex usage\nWeekly remaining: \(weekly.remainingPercent)% · resets \(weeklyReset)"
    }
}

struct UsageWindow: Sendable {
    let remainingPercent: Int
    let windowDurationMins: Double?
    let resetsAt: Date?

    init(_ window: RateLimitWindow) {
        let used = min(100, max(0, window.usedPercent ?? 0))
        remainingPercent = min(100, max(0, Int((100 - used).rounded())))
        windowDurationMins = window.windowDurationMins
        resetsAt = window.resetsAt.map { Date(timeIntervalSince1970: $0) }
    }

    func displayText(formatter: DateFormatter) -> String {
        guard let resetsAt else {
            return "\(remainingPercent)% remaining, reset unknown"
        }
        return "\(remainingPercent)% remaining, resets \(formatter.string(from: resetsAt))"
    }
}

private func approximately(_ value: Double?, _ target: Double) -> Bool {
    guard let value else {
        return false
    }
    return abs(value - target) <= 1
}
