import AppKit
import Foundation
import XCTest
@testable import CodexUsageStatus

final class CodexUsageStatusTests: XCTestCase {
    func testCodexSingle30DayAndDualWindows() throws {
        let single30d = try UsageSummary(response: RateLimitsResponse(
            rateLimits: nil,
            rateLimitsByLimitId: [
                "codex": RateLimitSnapshot(
                    limitId: "codex",
                    primary: RateLimitWindow(usedPercent: 12, windowDurationMins: 43_200, resetsAt: 1_780_000_000),
                    secondary: nil,
                    planType: "pro"
                )
            ]
        ))
        XCTAssertNil(single30d.fiveHour)
        XCTAssertEqual(single30d.weekly.shortLabel, "30D")
        XCTAssertEqual(single30d.weekly.remainingPercent, 88)

        let dual = try UsageSummary(response: RateLimitsResponse(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                primary: RateLimitWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: 1_780_000_000),
                secondary: RateLimitWindow(usedPercent: 45, windowDurationMins: 43_200, resetsAt: 1_782_000_000),
                planType: "pro"
            ),
            rateLimitsByLimitId: nil
        ))
        XCTAssertEqual(dual.fiveHour?.shortLabel, "5H")
        XCTAssertEqual(dual.fiveHour?.remainingPercent, 80)
        XCTAssertEqual(dual.weekly.shortLabel, "30D")
        XCTAssertEqual(dual.weekly.remainingPercent, 55)
    }

    func testExpiredWindowRollover() {
        let now = Date()
        let activeFiveHour = UsageWindow(remainingPercent: 60, windowDurationMins: 300, resetsAt: now.addingTimeInterval(3600))
        let expiredWeekly = UsageWindow(remainingPercent: 9, windowDurationMins: 10_080, resetsAt: now.addingTimeInterval(-300))
        let summary = UsageSummary(shortLabel: "A", title: "Claude & GPT", fiveHour: activeFiveHour, weekly: expiredWeekly)

        let rolled = summary.rollingOverExpiredWindows(at: now)
        XCTAssertEqual(rolled.fiveHour?.remainingPercent, 60)
        XCTAssertEqual(rolled.weekly.remainingPercent, 100)
        XCTAssertNil(rolled.weekly.resetsAt)
    }

    func testQuotaVisibilityAlwaysKeepsAtLeastOneVisible() {
        var vis = QuotaVisibility()
        XCTAssertTrue(vis.toggle(.codex))
        XCTAssertTrue(vis.toggle(.gemini))
        XCTAssertFalse(vis.canHide(.claudeGpt))
        XCTAssertFalse(vis.toggle(.claudeGpt))
        XCTAssertEqual(vis.visibleProviders, [.claudeGpt])

        XCTAssertTrue(vis.toggle(.codex))
        XCTAssertEqual(vis.visibleProviders, [.codex, .claudeGpt])
    }

    func testLowQuotaAlertTrackerDeduplicatesPerCycleAndIgnoresJitter() {
        let now = Date()
        let resetBase = Date(timeIntervalSince1970: 1_780_000_200)
        let resetJittered = Date(timeIntervalSince1970: 1_780_000_205)
        let nextCycleReset = resetBase.addingTimeInterval(7 * 86_400)

        let makeUsage = { (percent: Int, reset: Date) in
            CombinedUsageSummary(
                codex: UsageSummary(shortLabel: "C", title: "Codex", fiveHour: nil, weekly: UsageWindow(remainingPercent: 100, windowDurationMins: 43_200, resetsAt: reset)),
                gemini: nil,
                claudeGpt: UsageSummary(shortLabel: "A", title: "Claude", fiveHour: UsageWindow(remainingPercent: 60, windowDurationMins: 300, resetsAt: reset), weekly: UsageWindow(remainingPercent: percent, windowDurationMins: 10_080, resetsAt: reset)),
                codexError: nil,
                antigravityError: nil
            )
        }

        var tracker = LowQuotaAlertTracker(isEnabled: true, notifiedCycles: [])
        // 15% does NOT trigger
        XCTAssertTrue(tracker.evaluate(usage: makeUsage(15, resetBase), visibility: QuotaVisibility(), now: now).isEmpty)
        // 14% triggers once
        let first = tracker.evaluate(usage: makeUsage(14, resetBase), visibility: QuotaVisibility(), now: now)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.provider, .claudeGpt)
        XCTAssertEqual(first.first?.windowLabel, "7D")
        // Jittered timestamp in same cycle does NOT re-trigger
        XCTAssertTrue(tracker.evaluate(usage: makeUsage(9, resetJittered), visibility: QuotaVisibility(), now: now).isEmpty)
        // Next weekly reset cycle triggers cleanly
        let nextWeek = tracker.evaluate(usage: makeUsage(12, nextCycleReset), visibility: QuotaVisibility(), now: now)
        XCTAssertEqual(nextWeek.count, 1)
    }

    func testTokenPrioritizationCacheHitAndZeroCopyScanner() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cus-tests-\(UUID().uuidString)", isDirectory: true)
        let sessionDir = tempDir.appendingPathComponent("sessions/2026/11/28", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        setenv("CODEX_HOME", tempDir.path, 1)
        defer { unsetenv("CODEX_HOME") }

        let rollout = sessionDir.appendingPathComponent("rollout-2026-11-28T09-00-00-test.jsonl")
        let iso = ISO8601DateFormatter()
        let todayStr = iso.string(from: Date().addingTimeInterval(-60))
        let threeDaysAgoStr = iso.string(from: Date().addingTimeInterval(-3 * 86_400))
        let largeFiller = String(repeating: "z", count: 270_000)

        let part1 = [
            #"{"type":"turn_context","payload":{"model":"gpt-old-heavy"}}"#,
            #"{"timestamp":""# + threeDaysAgoStr + #"","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":90000,"cached_input_tokens":81000,"output_tokens":5000,"reasoning_output_tokens":1000,"total_tokens":95000},"last_token_usage":{"input_tokens":90000,"cached_input_tokens":81000,"output_tokens":5000,"reasoning_output_tokens":1000,"total_tokens":95000}}}}"#,
            #"{"type":"noise","blob":""# + largeFiller + #""}"#,
            #"{"type":"turn_context","payload":{"model":"gpt-today-active"}}"#,
            #"{"timestamp":""# + todayStr + #"","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100000,"cached_input_tokens":90000,"output_tokens":6000,"reasoning_output_tokens":1200,"total_tokens":106000},"last_token_usage":{"input_tokens":10000,"cached_input_tokens":9000,"output_tokens":1000,"reasoning_output_tokens":200,"total_tokens":11000}}}}"#,
        ].joined(separator: "\n") + "\n"

        let trailingFull = #"{"timestamp":""# + todayStr + #"","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":102000,"cached_input_tokens":91500,"output_tokens":6500,"reasoning_output_tokens":1300,"total_tokens":108500},"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1500,"output_tokens":500,"reasoning_output_tokens":100,"total_tokens":2500}}}}"# + "\n"
        try (part1 + trailingFull.prefix(32)).write(to: rollout, atomically: false, encoding: .utf8)

        let scanner = TokenUsageScanner()
        let firstScan = scanner.scan()
        XCTAssertEqual(firstScan.total(provider: .codex, range: .today), TokenCounts(input: 1000, cacheRead: 9000, output: 1000, reasoning: 200, calls: 1))

        let handle = try FileHandle(forWritingTo: rollout)
        handle.seekToEndOfFile()
        handle.write(Data(trailingFull.dropFirst(32).utf8))
        try handle.close()

        let secondScan = scanner.scan()
        let freshScan = TokenUsageScanner().scan()
        XCTAssertEqual(secondScan.total(provider: .codex, range: .today), freshScan.total(provider: .codex, range: .today))
        XCTAssertEqual(secondScan.total(provider: .codex, range: .today).cacheHitPercent, 88)

        // Today-active model (13.5K today) must rank ahead of older 3d-ago model (95K window, 0 today)!
        let ranked = secondScan.prioritizedModels(provider: .codex)
        XCTAssertEqual(ranked.map(\.model), ["gpt-today-active", "gpt-old-heavy"])
        XCTAssertEqual(TokenFormat.displayModelName("system", chinese: true), "系统检查点 (checkpoint)")
    }

    @MainActor
    func testRedCapsuleBadgePixelsBelow15Percent() {
        _ = NSApplication.shared
        let dark = NSAppearance(named: .darkAqua)!
        let summary = CombinedUsageSummary(
            codex: nil,
            gemini: UsageSummary(
                shortLabel: "G",
                title: "G",
                fiveHour: UsageWindow(remainingPercent: 15, windowDurationMins: 300, resetsAt: Date().addingTimeInterval(3600)),
                weekly: UsageWindow(remainingPercent: 90, windowDurationMins: 10_080, resetsAt: Date().addingTimeInterval(86_400))
            ),
            claudeGpt: UsageSummary(
                shortLabel: "A",
                title: "A",
                fiveHour: UsageWindow(remainingPercent: 61, windowDurationMins: 300, resetsAt: Date().addingTimeInterval(3600)),
                weekly: UsageWindow(remainingPercent: 9, windowDurationMins: 10_080, resetsAt: Date().addingTimeInterval(86_400))
            ),
            codexError: nil,
            antigravityError: nil
        )

        let gImg = UsageBadgeRenderer.image(for: summary, style: .quotaAndResetTimes, visibility: QuotaVisibility(hidden: [.codex, .claudeGpt]), appearance: dark)
        let aImg = UsageBadgeRenderer.image(for: summary, style: .quotaAndResetTimes, visibility: QuotaVisibility(hidden: [.codex, .gemini]), appearance: dark)

        func countCrimson(_ img: NSImage) -> Int {
            guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return -1 }
            var count = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.7 else { continue }
                    if c.redComponent > 0.70 && c.greenComponent < 0.25 && c.blueComponent < 0.28 {
                        count += 1
                    }
                }
            }
            return count
        }

        XCTAssertEqual(countCrimson(gImg), 0)
        XCTAssertGreaterThan(countCrimson(aImg), 250)
    }
}
