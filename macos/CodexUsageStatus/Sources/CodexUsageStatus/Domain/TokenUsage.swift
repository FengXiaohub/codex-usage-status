import Foundation

/// Which menu-bar column a token record belongs to.
enum TokenProvider: String, CaseIterable, Sendable {
    case codex
    case gemini
    case claudeGpt

    var shortLabel: String {
        switch self {
        case .codex: return "C"
        case .gemini: return "G"
        case .claudeGpt: return "A"
        }
    }

    var menuPrefix: String {
        switch self {
        case .codex: return "[C] Codex"
        case .gemini: return "[G] Gemini"
        case .claudeGpt: return "[A] Claude & GPT"
        }
    }

    /// Antigravity records are split the same way as the quota groups: Claude / GPT models
    /// belong to the third-party group, everything else (Gemini, system checkpoints) to Gemini.
    static func antigravityProvider(forModel model: String) -> TokenProvider {
        let lowered = model.lowercased()
        if lowered.contains("claude") || lowered.contains("gpt") {
            return .claudeGpt
        }
        return .gemini
    }
}

enum TokenRange: Sendable {
    case today
    case lastDays
}

/// Normalized token counts. `input` never includes cached tokens; `output` includes reasoning.
struct TokenCounts: Sendable, Equatable {
    var input: Int64 = 0
    var cacheRead: Int64 = 0
    var output: Int64 = 0
    var reasoning: Int64 = 0
    var calls: Int = 0

    var total: Int64 {
        input + cacheRead + output
    }

    /// Share of prompt tokens served from cache (0...100), or `nil` when there are no cached tokens.
    var cacheHitPercent: Int? {
        let promptTotal = input + cacheRead
        guard cacheRead > 0, promptTotal > 0 else {
            return nil
        }
        return Int((Double(cacheRead) * 100.0 / Double(promptTotal)).rounded())
    }

    var isEmpty: Bool {
        total == 0 && calls == 0
    }

    mutating func add(_ other: TokenCounts) {
        input += other.input
        cacheRead += other.cacheRead
        output += other.output
        reasoning += other.reasoning
        calls += other.calls
    }
}

struct TokenBucketKey: Hashable, Sendable {
    /// Local calendar day encoded as yyyymmdd so it can be compared numerically.
    let day: Int
    let provider: TokenProvider
    let model: String
}

struct ModelTokenEntry: Sendable, Equatable {
    let model: String
    let today: TokenCounts
    let window: TokenCounts
}

struct TokenUsageReport: Sendable {
    let generatedAt: Date
    let todayKey: Int
    let windowStartKey: Int
    let windowDays: Int
    let buckets: [TokenBucketKey: TokenCounts]
    let scannedFiles: Int

    private func includes(_ day: Int, range: TokenRange) -> Bool {
        switch range {
        case .today:
            return day == todayKey
        case .lastDays:
            return day >= windowStartKey && day <= todayKey
        }
    }

    func total(provider: TokenProvider?, range: TokenRange) -> TokenCounts {
        var result = TokenCounts()
        for (key, counts) in buckets where includes(key.day, range: range) {
            if let provider, key.provider != provider {
                continue
            }
            result.add(counts)
        }
        return result
    }

    func counts(provider: TokenProvider, model: String, range: TokenRange) -> TokenCounts {
        var result = TokenCounts()
        for (key, counts) in buckets where key.provider == provider && key.model == model && includes(key.day, range: range) {
            result.add(counts)
        }
        return result
    }

    /// Models active in the window: models used today come first (sorted by today's tokens desc),
    /// followed by older models in the window (sorted by window tokens desc).
    func prioritizedModels(provider: TokenProvider) -> [ModelTokenEntry] {
        var todayByModel: [String: TokenCounts] = [:]
        var windowByModel: [String: TokenCounts] = [:]
        for (key, counts) in buckets where key.provider == provider && includes(key.day, range: .lastDays) {
            windowByModel[key.model, default: TokenCounts()].add(counts)
            if key.day == todayKey {
                todayByModel[key.model, default: TokenCounts()].add(counts)
            }
        }
        return windowByModel
            .map { ModelTokenEntry(model: $0.key, today: todayByModel[$0.key] ?? TokenCounts(), window: $0.value) }
            .filter { !$0.window.isEmpty }
            .sorted { lhs, rhs in
                let lhsActiveToday = lhs.today.total > 0
                let rhsActiveToday = rhs.today.total > 0
                if lhsActiveToday != rhsActiveToday {
                    return lhsActiveToday
                }
                if lhsActiveToday && lhs.today.total != rhs.today.total {
                    return lhs.today.total > rhs.today.total
                }
                if lhs.window.total != rhs.window.total {
                    return lhs.window.total > rhs.window.total
                }
                return lhs.model < rhs.model
            }
    }

    var textSummary: String {
        var lines: [String] = []
        for provider in TokenProvider.allCases {
            let today = total(provider: provider, range: .today)
            let window = total(provider: provider, range: .lastDays)
            lines.append("\(provider.menuPrefix): today \(TokenFormat.compact(today.total)) · \(windowDays)d \(TokenFormat.compact(window.total))")
            lines.append("  today: \(TokenFormat.breakdown(today, chinese: false))")
            lines.append("  \(windowDays)d: \(TokenFormat.breakdown(window, chinese: false))")
            for entry in prioritizedModels(provider: provider) {
                let label = TokenFormat.displayModelName(entry.model, chinese: false)
                lines.append("    \(label): today \(TokenFormat.compact(entry.today.total)) · \(windowDays)d \(TokenFormat.compact(entry.window.total)) (\(entry.window.calls) calls)")
            }
        }
        let today = total(provider: nil, range: .today)
        let window = total(provider: nil, range: .lastDays)
        lines.append("Total: today \(TokenFormat.compact(today.total)) · \(windowDays)d \(TokenFormat.compact(window.total)) · files scanned \(scannedFiles)")
        return lines.joined(separator: "\n")
    }
}

enum TokenFormat {
    static func compact(_ value: Int64) -> String {
        let number = Double(value)
        switch value {
        case ..<1_000:
            return "\(value)"
        case ..<1_000_000:
            return String(format: "%.1fK", number / 1_000)
        case ..<100_000_000:
            return String(format: "%.1fM", number / 1_000_000)
        case ..<1_000_000_000:
            return String(format: "%.0fM", number / 1_000_000)
        default:
            return String(format: "%.2fB", number / 1_000_000_000)
        }
    }

    static func displayModelName(_ raw: String, chinese: Bool) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.isEmpty || lowered == "system" || lowered == "none" {
            return chinese ? "系统检查点 (checkpoint)" : "system (checkpoint)"
        }
        return raw
    }

    static func breakdown(_ counts: TokenCounts, chinese: Bool) -> String {
        guard !counts.isEmpty else {
            return chinese ? "无记录" : "no records"
        }
        let cachedText: String
        if let hitPercent = counts.cacheHitPercent {
            cachedText = chinese
                ? "缓存 \(compact(counts.cacheRead)) (\(hitPercent)%)"
                : "cached \(compact(counts.cacheRead)) (\(hitPercent)%)"
        } else {
            cachedText = chinese ? "缓存 \(compact(counts.cacheRead))" : "cached \(compact(counts.cacheRead))"
        }
        let output: String
        if counts.reasoning > 0 {
            output = chinese
                ? "输出 \(compact(counts.output))（含推理 \(compact(counts.reasoning))）"
                : "output \(compact(counts.output)) (reasoning \(compact(counts.reasoning)))"
        } else {
            output = chinese ? "输出 \(compact(counts.output))" : "output \(compact(counts.output))"
        }
        if chinese {
            return "输入 \(compact(counts.input)) · \(cachedText) · \(output) · \(counts.calls) 次"
        }
        return "input \(compact(counts.input)) · \(cachedText) · \(output) · \(counts.calls) calls"
    }
}
