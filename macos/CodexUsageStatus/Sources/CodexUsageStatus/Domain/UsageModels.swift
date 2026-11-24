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

struct AntigravityUsageEnvelope: Decodable, Sendable {
    let status: String?
    let command: AntigravityCommandPayload?
}

struct AntigravityCommandPayload: Decodable, Sendable {
    let name: String?
    let data: AntigravityUsageData?
}

struct AntigravityUsageData: Decodable, Sendable {
    let groups: [AntigravityQuotaGroup]?
}

struct AntigravityQuotaGroup: Decodable, Sendable {
    let name: String?
    let buckets: [AntigravityQuotaBucket]?
}

struct AntigravityQuotaBucket: Decodable, Sendable {
    let id: String?
    let name: String?
    let window: String?
    let remainingFraction: Double?
    let resetTime: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case window
        case remainingFraction = "remaining_fraction"
        case resetTime = "reset_time"
    }
}

struct ProviderQuotaColumn: Sendable {
    let shortLabel: String
    let title: String
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    let errorDescription: String?

    var isAvailable: Bool {
        fiveHour != nil || weekly != nil
    }
}

struct CombinedUsageSummary: Sendable {
    let codex: UsageSummary?
    let gemini: UsageSummary?
    let claudeGpt: UsageSummary?
    let codexError: String?
    let antigravityError: String?

    var hasAnyUsage: Bool {
        codex != nil || gemini != nil || claudeGpt != nil
    }

    var columns: [ProviderQuotaColumn] {
        [
            ProviderQuotaColumn(
                shortLabel: "C",
                title: "Codex",
                fiveHour: codex?.fiveHour,
                weekly: codex?.weekly,
                errorDescription: codexError
            ),
            ProviderQuotaColumn(
                shortLabel: "G",
                title: "Antigravity Gemini",
                fiveHour: gemini?.fiveHour,
                weekly: gemini?.weekly,
                errorDescription: antigravityError
            ),
            ProviderQuotaColumn(
                shortLabel: "A",
                title: "Antigravity Claude & GPT",
                fiveHour: claudeGpt?.fiveHour,
                weekly: claudeGpt?.weekly,
                errorDescription: antigravityError
            ),
        ]
    }

    var menuTitle: String {
        columns.map { column in
            guard column.isAvailable else {
                return "\(column.shortLabel) --"
            }
            var parts: [String] = []
            if let fiveHour = column.fiveHour {
                parts.append("5h \(fiveHour.remainingPercent)%")
            }
            if let weekly = column.weekly {
                parts.append("7d \(weekly.remainingPercent)%")
            }
            return "\(column.shortLabel) \(parts.joined(separator: " "))"
        }.joined(separator: " | ")
    }

    var verboseTitle: String {
        columns.map { column in
            if column.isAvailable {
                var parts: [String] = []
                if let fiveHour = column.fiveHour {
                    parts.append("5-hour \(fiveHour.remainingPercent)%")
                }
                if let weekly = column.weekly {
                    parts.append("weekly \(weekly.remainingPercent)%")
                }
                return "[\(column.shortLabel)] \(column.title): \(parts.joined(separator: " · "))"
            } else if let err = column.errorDescription {
                return "[\(column.shortLabel)] \(column.title): \(err)"
            } else {
                return "[\(column.shortLabel)] \(column.title): unavailable"
            }
        }.joined(separator: "\n")
    }

    func tooltip(formatter: DateFormatter) -> String {
        columns.map { column in
            var lines = ["[\(column.shortLabel)] \(column.title)"]
            if column.isAvailable {
                if let fiveHour = column.fiveHour {
                    let reset = fiveHour.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
                    lines.append("  5H remaining: \(fiveHour.remainingPercent)% · resets \(reset)")
                }
                if let weekly = column.weekly {
                    let reset = weekly.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
                    lines.append("  7D remaining: \(weekly.remainingPercent)% · resets \(reset)")
                }
            } else if let err = column.errorDescription {
                lines.append("  Unavailable: \(err)")
            } else {
                lines.append("  Unavailable")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

struct UsageSummary: Sendable {
    let shortLabel: String
    let title: String
    let planType: String?
    let fiveHour: UsageWindow?
    let weekly: UsageWindow

    init(
        shortLabel: String = "C",
        title: String = "Codex",
        planType: String? = nil,
        fiveHour: UsageWindow?,
        weekly: UsageWindow
    ) {
        self.shortLabel = shortLabel
        self.title = title
        self.planType = planType
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

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

        self.shortLabel = "C"
        self.title = "Codex"
        self.planType = snapshot.planType
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    static func parseAntigravityGroups(from envelope: AntigravityUsageEnvelope) throws -> (gemini: UsageSummary?, claudeGpt: UsageSummary?) {
        guard let groups = envelope.command?.data?.groups, !groups.isEmpty else {
            throw FetchError.invalidOutput
        }

        let geminiGroup = groups.first { group in
            (group.name?.localizedCaseInsensitiveContains("gemini") == true)
                || (group.buckets?.contains { $0.id?.lowercased().hasPrefix("gemini") == true } == true)
        }

        let claudeGptGroup = groups.first { group in
            (group.name?.localizedCaseInsensitiveContains("claude") == true)
                || (group.name?.localizedCaseInsensitiveContains("gpt") == true)
                || (group.buckets?.contains { $0.id?.lowercased().hasPrefix("3p") == true } == true)
        }

        let gemini = geminiGroup.flatMap { Self.fromAntigravityGroup($0, shortLabel: "G", title: "Antigravity Gemini") }
        let claudeGpt = claudeGptGroup.flatMap { Self.fromAntigravityGroup($0, shortLabel: "A", title: "Antigravity Claude & GPT") }

        if gemini == nil && claudeGpt == nil {
            throw FetchError.invalidOutput
        }

        return (gemini, claudeGpt)
    }

    private static func fromAntigravityGroup(_ group: AntigravityQuotaGroup, shortLabel: String, title: String) -> UsageSummary? {
        let buckets = group.buckets ?? []
        let fiveHourBucket = buckets.first { bucket in
            bucket.window == "5h"
                || (bucket.id?.localizedCaseInsensitiveContains("5h") == true)
                || (bucket.name?.localizedCaseInsensitiveContains("five hour") == true)
        }
        let weeklyBucket = buckets.first { bucket in
            bucket.window == "weekly"
                || (bucket.id?.localizedCaseInsensitiveContains("weekly") == true)
                || (bucket.name?.localizedCaseInsensitiveContains("weekly") == true)
        }

        let fiveHour = fiveHourBucket.map { UsageWindow(antigravityBucket: $0, durationMins: 300) }
        let weekly = weeklyBucket.map { UsageWindow(antigravityBucket: $0, durationMins: 10080) } ?? fiveHour

        guard let weekly else {
            return nil
        }

        return UsageSummary(
            shortLabel: shortLabel,
            title: group.name ?? title,
            planType: nil,
            fiveHour: fiveHour,
            weekly: weekly
        )
    }

    var menuTitle: String {
        if let fiveHour {
            return "5h \(fiveHour.remainingPercent)% 7d \(weekly.remainingPercent)%"
        }
        return "7d \(weekly.remainingPercent)%"
    }

    var verboseTitle: String {
        if let fiveHour {
            return "\(title) usage: 5-hour \(fiveHour.remainingPercent)% · weekly \(weekly.remainingPercent)%"
        }
        return "\(title) usage: weekly \(weekly.remainingPercent)%"
    }

    func tooltip(formatter: DateFormatter) -> String {
        let weeklyReset = weekly.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        if let fiveHour {
            let fiveHourReset = fiveHour.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
            return "\(title) usage\n5-hour remaining: \(fiveHour.remainingPercent)% · resets \(fiveHourReset)\nWeekly remaining: \(weekly.remainingPercent)% · resets \(weeklyReset)"
        }
        return "\(title) usage\nWeekly remaining: \(weekly.remainingPercent)% · resets \(weeklyReset)"
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

    init(antigravityBucket: AntigravityQuotaBucket, durationMins: Double) {
        let fraction = min(1.0, max(0.0, antigravityBucket.remainingFraction ?? 0))
        remainingPercent = min(100, max(0, Int((fraction * 100).rounded())))
        windowDurationMins = durationMins
        resetsAt = antigravityBucket.resetTime.flatMap(Self.parseISO8601Date)
    }

    private static func parseISO8601Date(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: raw)
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
