import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let codexFiveHourItem = NSMenuItem(title: "[C] Codex 5H -- · 读取中", action: nil, keyEquivalent: "")
    private let codexWeeklyItem = NSMenuItem(title: "[C] Codex 7D -- · 读取中", action: nil, keyEquivalent: "")
    private let geminiFiveHourItem = NSMenuItem(title: "[G] Gemini 5H -- · 读取中", action: nil, keyEquivalent: "")
    private let geminiWeeklyItem = NSMenuItem(title: "[G] Gemini 7D -- · 读取中", action: nil, keyEquivalent: "")
    private let claudeGptFiveHourItem = NSMenuItem(title: "[A] Claude & GPT 5H -- · 读取中", action: nil, keyEquivalent: "")
    private let claudeGptWeeklyItem = NSMenuItem(title: "[A] Claude & GPT 7D -- · 读取中", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
    private let displayStyleItem = NSMenuItem(title: "Display Style", action: nil, keyEquivalent: "")
    private let displayStyleMenu = NSMenu()
    private let doubleRingItem = NSMenuItem(title: BadgeStyle.doubleRing.menuTitle, action: #selector(selectDoubleRingStyle), keyEquivalent: "")
    private let largeReadoutItem = NSMenuItem(title: BadgeStyle.largeReadout.menuTitle, action: #selector(selectLargeReadoutStyle), keyEquivalent: "")
    private let quotaAndResetTimesItem = NSMenuItem(title: BadgeStyle.quotaAndResetTimes.menuTitle, action: #selector(selectQuotaAndResetTimesStyle), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")

    private var timer: Timer?
    private var isRefreshing = false
    private let refreshInterval = configuredRefreshInterval()
    private var badgeStyle = BadgeStyle.load()
    private var lastUsage: CombinedUsageSummary?
    private var lastValidCodex: UsageSummary?
    private var lastValidGemini: UsageSummary?
    private var lastValidClaudeGpt: UsageSummary?
    private var consecutiveCodexFailures = 0
    private var consecutiveAntigravityFailures = 0
    private var lastRefreshDate: Date?
    private var lastError: Error?
    private var lastClientSignature: String = ""
    private var appearanceObservation: NSKeyValueObservation?

    private var usesChinese: Bool {
        Locale.current.language.languageCode?.identifier == "zh"
    }

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private lazy var weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: usesChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private lazy var dateAndTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: usesChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = usesChinese ? "M月d日 HH:mm" : "MMM d HH:mm"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let loadingText = usesChinese ? "读取中" : "Loading"
        codexFiveHourItem.title = "[C] Codex 5H -- · \(loadingText)"
        codexWeeklyItem.title = "[C] Codex 7D -- · \(loadingText)"
        geminiFiveHourItem.title = "[G] Gemini 5H -- · \(loadingText)"
        geminiWeeklyItem.title = "[G] Gemini 7D -- · \(loadingText)"
        claudeGptFiveHourItem.title = "[A] Claude & GPT 5H -- · \(loadingText)"
        claudeGptWeeklyItem.title = "[A] Claude & GPT 7D -- · \(loadingText)"

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "Codex & Antigravity usage: waiting for first refresh"
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.renderCurrentBadge()
                }
            }
        }
        renderCurrentBadge()

        menu.addItem(codexFiveHourItem)
        menu.addItem(codexWeeklyItem)
        menu.addItem(.separator())
        menu.addItem(geminiFiveHourItem)
        menu.addItem(geminiWeeklyItem)
        menu.addItem(.separator())
        menu.addItem(claudeGptFiveHourItem)
        menu.addItem(claudeGptWeeklyItem)
        menu.addItem(.separator())

        refreshItem.target = self
        menu.addItem(refreshItem)

        doubleRingItem.target = self
        largeReadoutItem.target = self
        quotaAndResetTimesItem.target = self
        displayStyleMenu.addItem(doubleRingItem)
        displayStyleMenu.addItem(largeReadoutItem)
        displayStyleMenu.addItem(quotaAndResetTimesItem)
        displayStyleItem.submenu = displayStyleMenu
        menu.addItem(displayStyleItem)
        updateStyleMenuState()

        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        lastClientSignature = Self.currentClientSignature()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWakeOrActivate),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWakeOrActivate),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        refresh()
    }

    @objc private func workspaceDidWakeOrActivate(_ notification: Notification) {
        if notification.name == NSWorkspace.didWakeNotification {
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConfig.wakeRefreshDelay) { [weak self] in
                guard let self else { return }
                self.lastClientSignature = Self.currentClientSignature()
                self.refresh()
            }
            return
        }

        let newSignature = Self.currentClientSignature()
        if newSignature != lastClientSignature {
            lastClientSignature = newSignature
            refresh()
            return
        }
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let name = app.localizedName?.lowercased(),
           name.contains("antigravity") || name.contains("chatgpt") || name.contains("codex") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.refresh()
            }
        }
    }

    private static func currentClientSignature() -> String {
        AppConfig.watchedClientPaths.map { path in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let mtime = attrs[.modificationDate] as? Date else {
                return "\(path):missing"
            }
            return "\(path):\(Int(mtime.timeIntervalSince1970))"
        }.joined(separator: "|")
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func timerDidFire() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func selectDoubleRingStyle() {
        setBadgeStyle(.doubleRing)
    }

    @objc private func selectLargeReadoutStyle() {
        setBadgeStyle(.largeReadout)
    }

    @objc private func selectQuotaAndResetTimesStyle() {
        setBadgeStyle(.quotaAndResetTimes)
    }

    @objc private func showSettings() {
        let status: String
        if let lastError {
            status = "Last refresh failed: \(lastError.localizedDescription)"
        } else if let lastUsage {
            status = lastUsage.verboseTitle
        } else {
            status = "Waiting for first refresh"
        }

        let lastRefresh = lastRefreshDate.map { dateFormatter.string(from: $0) } ?? "Never"
        let message = """
        \(status)

        Display style: \(badgeStyle.menuTitle)
        Refresh interval: \(Int(refreshInterval)) seconds
        Failure retry: \(Int(AppConfig.errorRetryInterval)) seconds
        Last refresh: \(lastRefresh)
        Data sources: local Codex app-server & Antigravity CLI (agy /usage)
        """

        let alert = NSAlert()
        alert.messageText = "Codex & Antigravity Usage Status"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func setBadgeStyle(_ style: BadgeStyle) {
        guard badgeStyle != style else {
            return
        }
        badgeStyle = style
        badgeStyle.save()
        updateStyleMenuState()
        renderCurrentBadge()
    }

    private func updateStyleMenuState() {
        doubleRingItem.state = badgeStyle == .doubleRing ? .on : .off
        largeReadoutItem.state = badgeStyle == .largeReadout ? .on : .off
        quotaAndResetTimesItem.state = badgeStyle == .quotaAndResetTimes ? .on : .off
    }

    private func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        refreshItem.isEnabled = false
        refreshItem.title = "Refreshing..."

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let usage = try await CodexUsageFetcher.fetchCombined()
                self.isRefreshing = false
                self.refreshItem.isEnabled = true
                self.refreshItem.title = "Refresh"
                let hadTransientFailure = self.applyUsage(usage)
                self.scheduleNextRefresh(after: hadTransientFailure ? AppConfig.transientRetryInterval : self.refreshInterval)
            } catch {
                self.isRefreshing = false
                self.refreshItem.isEnabled = true
                self.refreshItem.title = "Refresh"
                let retainedStale = self.applyError(error)
                self.scheduleNextRefresh(after: retainedStale ? AppConfig.transientRetryInterval : AppConfig.errorRetryInterval)
            }
        }
    }

    private func scheduleNextRefresh(after seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: seconds, target: self, selector: #selector(timerDidFire), userInfo: nil, repeats: false)
    }

    @discardableResult
    private func applyUsage(_ usage: CombinedUsageSummary) -> Bool {
        var resolvedCodex = usage.codex
        var resolvedCodexError = usage.codexError
        var hadTransientFailure = false

        if let codex = usage.codex {
            lastValidCodex = codex
            consecutiveCodexFailures = 0
        } else {
            consecutiveCodexFailures += 1
            if consecutiveCodexFailures <= AppConfig.maxStaleFailuresBeforeError, let cached = lastValidCodex {
                resolvedCodex = cached
                resolvedCodexError = nil
                hadTransientFailure = true
            }
        }

        var resolvedGemini = usage.gemini
        var resolvedClaudeGpt = usage.claudeGpt
        var resolvedAgyError = usage.antigravityError

        if usage.gemini != nil || usage.claudeGpt != nil {
            if let gemini = usage.gemini { lastValidGemini = gemini }
            if let claudeGpt = usage.claudeGpt { lastValidClaudeGpt = claudeGpt }
            consecutiveAntigravityFailures = 0
        } else {
            consecutiveAntigravityFailures += 1
            if consecutiveAntigravityFailures <= AppConfig.maxStaleFailuresBeforeError,
               (lastValidGemini != nil || lastValidClaudeGpt != nil) {
                resolvedGemini = lastValidGemini
                resolvedClaudeGpt = lastValidClaudeGpt
                resolvedAgyError = nil
                hadTransientFailure = true
            }
        }

        let merged = CombinedUsageSummary(
            codex: resolvedCodex,
            gemini: resolvedGemini,
            claudeGpt: resolvedClaudeGpt,
            codexError: resolvedCodexError,
            antigravityError: resolvedAgyError
        )

        lastUsage = merged
        lastRefreshDate = Date()
        lastError = nil
        updateExpiryItems(for: merged)
        renderCurrentBadge()
        return hadTransientFailure
    }

    @discardableResult
    private func applyError(_ error: Error) -> Bool {
        consecutiveCodexFailures += 1
        consecutiveAntigravityFailures += 1

        if consecutiveCodexFailures <= AppConfig.maxStaleFailuresBeforeError,
           consecutiveAntigravityFailures <= AppConfig.maxStaleFailuresBeforeError,
           let cachedUsage = lastUsage,
           cachedUsage.hasAnyUsage {
            return true
        }

        lastError = error
        let failureText = usesChinese ? "读取失败" : "Unavailable"
        codexFiveHourItem.isHidden = false
        codexFiveHourItem.title = "[C] Codex 5H -- · \(failureText)"
        codexWeeklyItem.title = "[C] Codex 7D -- · \(failureText)"
        geminiFiveHourItem.isHidden = false
        geminiFiveHourItem.title = "[G] Gemini 5H -- · \(failureText)"
        geminiWeeklyItem.title = "[G] Gemini 7D -- · \(failureText)"
        claudeGptFiveHourItem.isHidden = false
        claudeGptFiveHourItem.title = "[A] Claude & GPT 5H -- · \(failureText)"
        claudeGptWeeklyItem.title = "[A] Claude & GPT 7D -- · \(failureText)"
        renderCurrentBadge()
        return false
    }

    private func updateExpiryItems(for usage: CombinedUsageSummary) {
        updateGroupMenuItems(
            prefix: "[C] Codex",
            summary: usage.codex,
            fiveHourItem: codexFiveHourItem,
            weeklyItem: codexWeeklyItem
        )
        updateGroupMenuItems(
            prefix: "[G] Gemini",
            summary: usage.gemini,
            fiveHourItem: geminiFiveHourItem,
            weeklyItem: geminiWeeklyItem
        )
        updateGroupMenuItems(
            prefix: "[A] Claude & GPT",
            summary: usage.claudeGpt,
            fiveHourItem: claudeGptFiveHourItem,
            weeklyItem: claudeGptWeeklyItem
        )
    }

    private func updateGroupMenuItems(
        prefix: String,
        summary: UsageSummary?,
        fiveHourItem: NSMenuItem,
        weeklyItem: NSMenuItem
    ) {
        guard let summary else {
            let failureText = usesChinese ? "读取失败" : "Unavailable"
            fiveHourItem.isHidden = false
            fiveHourItem.title = "\(prefix) 5H -- · \(failureText)"
            weeklyItem.title = "\(prefix) 7D -- · \(failureText)"
            return
        }

        fiveHourItem.isHidden = summary.fiveHour == nil
        if let fiveHour = summary.fiveHour {
            fiveHourItem.title = "\(prefix) 5H \(fiveHour.remainingPercent)% · \(expiryText(for: fiveHour.resetsAt))"
        }
        weeklyItem.title = "\(prefix) 7D \(summary.weekly.remainingPercent)% · \(expiryText(for: summary.weekly.resetsAt))"
    }

    private func expiryText(for date: Date?) -> String {
        guard let date else {
            return "未知"
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if calendar.isDateInTomorrow(date) {
            return usesChinese
                ? "明天 \(timeFormatter.string(from: date))"
                : "Tomorrow \(timeFormatter.string(from: date))"
        }
        if let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()), date < nextWeek {
            return "\(weekdayFormatter.string(from: date)) \(timeFormatter.string(from: date))"
        }
        return dateAndTimeFormatter.string(from: date)
    }

    private func renderCurrentBadge() {
        guard let button = statusItem.button else {
            return
        }

        let image: NSImage
        let tooltip: String
        if let lastError {
            image = UsageBadgeRenderer.errorImage(style: badgeStyle, appearance: button.effectiveAppearance)
            tooltip = "Codex & Antigravity usage: \(lastError.localizedDescription)"
        } else if let lastUsage {
            image = UsageBadgeRenderer.image(for: lastUsage, style: badgeStyle, appearance: button.effectiveAppearance)
            tooltip = lastUsage.tooltip(formatter: dateFormatter)
        } else {
            image = UsageBadgeRenderer.placeholderImage(style: badgeStyle, appearance: button.effectiveAppearance)
            tooltip = "Codex & Antigravity usage: waiting for first refresh"
        }

        statusItem.length = image.size.width
        button.title = ""
        button.image = image
        button.toolTip = tooltip
    }
}
