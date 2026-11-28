import Foundation
import UserNotifications

struct LowQuotaAlert: Equatable, Sendable {
    let cycleKey: String
    let provider: TokenProvider
    let windowLabel: String
    let remainingPercent: Int
    let resetsAt: Date?
}

/// Tracks which `< 15%` quota windows have already triggered a notification in their current reset cycle,
/// ensuring at most one notification per `(provider, window, resetCycle)` even across app restarts.
struct LowQuotaAlertTracker: Sendable {
    private static let enabledDefaultsKey = "LowQuotaNotificationsEnabled"
    private static let notifiedCyclesDefaultsKey = "NotifiedLowQuotaCycles"
    private static let maxStoredCycles = 32

    var isEnabled: Bool
    private(set) var notifiedCycles: [String]

    init(isEnabled: Bool = true, notifiedCycles: [String] = []) {
        self.isEnabled = isEnabled
        self.notifiedCycles = Array(notifiedCycles.suffix(Self.maxStoredCycles))
    }

    static func load(from defaults: UserDefaults = .standard) -> LowQuotaAlertTracker {
        let enabled: Bool
        if defaults.object(forKey: enabledDefaultsKey) == nil {
            enabled = true
        } else {
            enabled = defaults.bool(forKey: enabledDefaultsKey)
        }
        let cycles = defaults.stringArray(forKey: notifiedCyclesDefaultsKey) ?? []
        return LowQuotaAlertTracker(isEnabled: enabled, notifiedCycles: cycles)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
        defaults.set(Array(notifiedCycles.suffix(Self.maxStoredCycles)), forKey: Self.notifiedCyclesDefaultsKey)
    }

    mutating func evaluate(
        usage: CombinedUsageSummary,
        visibility: QuotaVisibility,
        threshold: Int = AppConfig.lowQuotaRedThresholdPercent,
        now: Date = Date()
    ) -> [LowQuotaAlert] {
        guard isEnabled else {
            return []
        }

        let groups: [(TokenProvider, UsageSummary?)] = [
            (.codex, usage.codex),
            (.gemini, usage.gemini),
            (.claudeGpt, usage.claudeGpt),
        ]

        var triggered: [LowQuotaAlert] = []
        for (provider, summary) in groups where visibility.isVisible(provider) {
            guard let summary else { continue }
            var candidates: [(String, UsageWindow)] = []
            if let fiveHour = summary.fiveHour {
                candidates.append(("5H", fiveHour))
            }
            let weeklyLabel = summary.weekly.shortLabel
            if summary.fiveHour == nil || weeklyLabel != "5H" {
                candidates.append((weeklyLabel, summary.weekly))
            }

            for (label, window) in candidates where window.remainingPercent < threshold {
                let key = Self.cycleKey(provider: provider, windowLabel: label, resetsAt: window.resetsAt, now: now)
                guard !notifiedCycles.contains(key) else {
                    continue
                }
                notifiedCycles.append(key)
                if notifiedCycles.count > Self.maxStoredCycles {
                    notifiedCycles.removeFirst(notifiedCycles.count - Self.maxStoredCycles)
                }
                triggered.append(
                    LowQuotaAlert(
                        cycleKey: key,
                        provider: provider,
                        windowLabel: label,
                        remainingPercent: window.remainingPercent,
                        resetsAt: window.resetsAt
                    )
                )
            }
        }
        return triggered
    }

    /// Rounds `resetsAt` into 30-minute buckets so minor server timestamp jitter never re-triggers an alert,
    /// while a real 5-hour or weekly reset always produces a distinct key.
    static func cycleKey(provider: TokenProvider, windowLabel: String, resetsAt: Date?, now: Date) -> String {
        let stamp: String
        if let resetsAt {
            let bucket = Int((resetsAt.timeIntervalSince1970 / 1800.0).rounded())
            stamp = "r\(bucket)"
        } else {
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: now)
            stamp = "d\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
        }
        return "\(provider.rawValue):\(windowLabel):\(stamp)"
    }
}

enum LowQuotaNotifier {
    private static var hasAppBundleContext: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestAuthorizationIfNeeded() {
        guard hasAppBundleContext else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func deliver(_ alerts: [LowQuotaAlert], chinese: Bool, resetText: (Date?) -> String) {
        guard !alerts.isEmpty, hasAppBundleContext else { return }
        let payloads: [(id: String, title: String, body: String)] = alerts.map { alert in
            let title = chinese
                ? "配额低于 \(AppConfig.lowQuotaRedThresholdPercent)% 提醒"
                : "Quota Below \(AppConfig.lowQuotaRedThresholdPercent)%"
            let reset = resetText(alert.resetsAt)
            let body = chinese
                ? "\(alert.provider.menuPrefix) \(alert.windowLabel) 剩余 \(alert.remainingPercent)%（重置：\(reset)）"
                : "\(alert.provider.menuPrefix) \(alert.windowLabel) remaining: \(alert.remainingPercent)% (resets \(reset))"
            return (id: "low-quota-\(alert.cycleKey)", title: title, body: body)
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let center = UNUserNotificationCenter.current()
            for payload in payloads {
                let content = UNMutableNotificationContent()
                content.title = payload.title
                content.body = payload.body
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: payload.id,
                    content: content,
                    trigger: nil
                )
                center.add(request)
            }
        }
    }
}
