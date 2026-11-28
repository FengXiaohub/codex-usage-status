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
    let response: AntigravityUsageData?

    var groups: [AntigravityQuotaGroup]? {
        response?.groups ?? command?.data?.groups
    }
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

    enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case buckets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        self.buckets = try container.decodeIfPresent([AntigravityQuotaBucket].self, forKey: .buckets)
    }
}

struct AntigravityQuotaBucket: Decodable, Sendable {
    let id: String?
    let name: String?
    let window: String?
    let remainingFraction: Double?
    let resetTime: String?

    enum CodingKeys: String, CodingKey {
        case id
        case bucketId
        case name
        case displayName
        case window
        case remainingFraction
        case remainingFractionSnake = "remaining_fraction"
        case resetTime
        case resetTimeSnake = "reset_time"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .bucketId)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        self.window = try container.decodeIfPresent(String.self, forKey: .window)
        self.remainingFraction = try container.decodeIfPresent(Double.self, forKey: .remainingFraction)
            ?? container.decodeIfPresent(Double.self, forKey: .remainingFractionSnake)
        self.resetTime = try container.decodeIfPresent(String.self, forKey: .resetTime)
            ?? container.decodeIfPresent(String.self, forKey: .resetTimeSnake)
    }
}

struct ProviderQuotaColumn: Sendable {
    let provider: TokenProvider
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

    func hasAnyUsage(for visibility: QuotaVisibility) -> Bool {
        columns(for: visibility).contains { $0.isAvailable }
    }

    func hasAnyError(for visibility: QuotaVisibility) -> Bool {
        columns(for: visibility).contains { $0.errorDescription != nil }
    }

    var columns: [ProviderQuotaColumn] {
        [
            ProviderQuotaColumn(
                provider: .codex,
                shortLabel: "C",
                title: "Codex",
                fiveHour: codex?.fiveHour,
                weekly: codex?.weekly,
                errorDescription: codexError
            ),
            ProviderQuotaColumn(
                provider: .gemini,
                shortLabel: "G",
                title: "Antigravity Gemini",
                fiveHour: gemini?.fiveHour,
                weekly: gemini?.weekly,
                errorDescription: antigravityError
            ),
            ProviderQuotaColumn(
                provider: .claudeGpt,
                shortLabel: "A",
                title: "Antigravity Claude & GPT",
                fiveHour: claudeGpt?.fiveHour,
                weekly: claudeGpt?.weekly,
                errorDescription: antigravityError
            ),
        ]
    }

    func columns(for visibility: QuotaVisibility) -> [ProviderQuotaColumn] {
        columns.filter { visibility.isVisible($0.provider) }
    }

    var menuTitle: String {
        menuTitle(for: QuotaVisibility())
    }

    func menuTitle(for visibility: QuotaVisibility) -> String {
        columns(for: visibility).map { column in
            guard column.isAvailable else {
                return "\(column.shortLabel) --"
            }
            var parts: [String] = []
            if let fiveHour = column.fiveHour {
                parts.append("5h \(fiveHour.remainingPercent)%")
            }
            if let weekly = column.weekly {
                parts.append("\(weekly.shortLabel.lowercased()) \(weekly.remainingPercent)%")
            }
            return "\(column.shortLabel) \(parts.joined(separator: " "))"
        }.joined(separator: " | ")
    }

    var verboseTitle: String {
        verboseTitle(for: QuotaVisibility())
    }

    func verboseTitle(for visibility: QuotaVisibility) -> String {
        columns(for: visibility).map { column in
            if column.isAvailable {
                var parts: [String] = []
                if let fiveHour = column.fiveHour {
                    parts.append("5-hour \(fiveHour.remainingPercent)%")
                }
                if let weekly = column.weekly {
                    parts.append("\(weekly.longLabel.lowercased()) \(weekly.remainingPercent)%")
                }
                return "[\(column.shortLabel)] \(column.title): \(parts.joined(separator: " · "))"
            } else if let err = column.errorDescription {
                return "[\(column.shortLabel)] \(column.title): \(err)"
            } else {
                return "[\(column.shortLabel)] \(column.title): unavailable"
            }
        }.joined(separator: "\n")
    }

    func tooltip(formatter: DateFormatter, visibility: QuotaVisibility = QuotaVisibility()) -> String {
        columns(for: visibility).map { column in
            var lines = ["[\(column.shortLabel)] \(column.title)"]
            if column.isAvailable {
                if let fiveHour = column.fiveHour {
                    let reset = fiveHour.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
                    lines.append("  5H remaining: \(fiveHour.remainingPercent)% · resets \(reset)")
                }
                if let weekly = column.weekly {
                    let reset = weekly.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
                    lines.append("  \(weekly.shortLabel) remaining: \(weekly.remainingPercent)% · resets \(reset)")
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
        // Exclude the 5-hour window so a 30-day secondary window is never shadowed by `windows.first`.
        let longWindows = windows.filter { !approximately($0.windowDurationMins, 300) }
        let weekly = longWindows.first { approximately($0.windowDurationMins, 10080) }
            ?? longWindows.max { ($0.windowDurationMins ?? 0) < ($1.windowDurationMins ?? 0) }
            ?? fiveHour

        guard let weekly else {
            throw FetchError.invalidOutput
        }

        self.shortLabel = "C"
        self.title = "Codex"
        self.planType = snapshot.planType
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    /// Rolls any cached window whose reset timestamp has already passed back to 100% (`resetsAt: nil`),
    /// preventing stale low-quota alerts while a companion desktop app is closed across a reset boundary.
    func rollingOverExpiredWindows(at now: Date = Date()) -> UsageSummary {
        UsageSummary(
            shortLabel: shortLabel,
            title: title,
            planType: planType,
            fiveHour: fiveHour?.rollingOverIfExpired(at: now),
            weekly: weekly.rollingOverIfExpired(at: now)
        )
    }

    static func parseAntigravityGroups(from envelope: AntigravityUsageEnvelope) throws -> (gemini: UsageSummary?, claudeGpt: UsageSummary?) {
        guard let groups = envelope.groups, !groups.isEmpty else {
            throw FetchError.invalidOutput
        }

        let geminiGroup = groups.first { group in
            (group.name?.localizedCaseInsensitiveContains("gemini") == true)
                || (group.buckets?.contains { $0.id?.lowercased().hasPrefix("gemini") == true } == true)
        } ?? groups.first

        let claudeGptGroup = groups.first { group in
            (group.name?.localizedCaseInsensitiveContains("claude") == true)
                || (group.name?.localizedCaseInsensitiveContains("gpt") == true)
                || (group.buckets?.contains { $0.id?.lowercased().hasPrefix("3p") == true } == true)
        } ?? (groups.count > 1 ? groups[1] : nil)

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
}

struct UsageWindow: Sendable {
    let remainingPercent: Int
    let windowDurationMins: Double?
    let resetsAt: Date?

    init(remainingPercent: Int, windowDurationMins: Double?, resetsAt: Date?) {
        self.remainingPercent = remainingPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

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
        resetsAt = antigravityBucket.resetTime.flatMap { ISO8601Parser.shared.parse($0) }
    }

    func rollingOverIfExpired(at now: Date, graceSeconds: TimeInterval = 60) -> UsageWindow {
        guard let resetsAt, resetsAt.timeIntervalSince(now) < -graceSeconds else {
            return self
        }
        return UsageWindow(remainingPercent: 100, windowDurationMins: windowDurationMins, resetsAt: nil)
    }

    /// Short label derived from the real window length, e.g. "5H", "7D" or "30D".
    var shortLabel: String {
        guard let mins = windowDurationMins, mins > 0 else {
            return "7D"
        }
        if approximately(mins, 300) {
            return "5H"
        }
        if mins >= 1440 {
            return "\(Int((mins / 1440).rounded()))D"
        }
        return "\(max(1, Int((mins / 60).rounded())))H"
    }

    /// Human readable window name for tooltips, e.g. "5-hour", "Weekly", "30-day".
    var longLabel: String {
        switch shortLabel {
        case "5H": return "5-hour"
        case "7D": return "Weekly"
        default:
            let label = shortLabel
            let number = label.dropLast()
            return label.hasSuffix("D") ? "\(number)-day" : "\(number)-hour"
        }
    }
}

private final class ISO8601Parser: @unchecked Sendable {
    static let shared = ISO8601Parser()

    private let lock = NSLock()
    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func parse(_ raw: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return fractional.date(from: raw) ?? standard.date(from: raw)
    }
}

private func approximately(_ value: Double?, _ target: Double) -> Bool {
    guard let value else {
        return false
    }
    return abs(value - target) <= 1
}
