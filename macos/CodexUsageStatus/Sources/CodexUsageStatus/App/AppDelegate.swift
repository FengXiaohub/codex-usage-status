import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let fiveHourExpiryItem = NSMenuItem(title: "5H -- · 读取中", action: nil, keyEquivalent: "")
    private let weeklyExpiryItem = NSMenuItem(title: "7D -- · 读取中", action: nil, keyEquivalent: "")
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
    private var lastUsage: UsageSummary?
    private var lastRefreshDate: Date?
    private var lastError: Error?

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
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)

        fiveHourExpiryItem.title = "5H -- · \(usesChinese ? "读取中" : "Loading")"
        weeklyExpiryItem.title = "7D -- · \(usesChinese ? "读取中" : "Loading")"

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "Codex usage: waiting for first refresh"
        }
        renderCurrentBadge()

        menu.addItem(fiveHourExpiryItem)
        menu.addItem(weeklyExpiryItem)
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
        refresh()
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
        Data source: local Codex app-server
        """

        let alert = NSAlert()
        alert.messageText = "Codex Usage Status"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
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
                let usage = try await CodexUsageFetcher.fetch()
                self.isRefreshing = false
                self.refreshItem.isEnabled = true
                self.refreshItem.title = "Refresh"
                self.applyUsage(usage)
                self.scheduleNextRefresh(after: self.refreshInterval)
            } catch {
                self.isRefreshing = false
                self.refreshItem.isEnabled = true
                self.refreshItem.title = "Refresh"
                self.applyError(error)
                self.scheduleNextRefresh(after: AppConfig.errorRetryInterval)
            }
        }
    }

    private func scheduleNextRefresh(after seconds: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: seconds, target: self, selector: #selector(timerDidFire), userInfo: nil, repeats: false)
    }

    private func applyUsage(_ usage: UsageSummary) {
        lastUsage = usage
        lastRefreshDate = Date()
        lastError = nil
        updateExpiryItems(for: usage)
        renderCurrentBadge()
    }

    private func applyError(_ error: Error) {
        lastError = error
        let failureText = usesChinese ? "读取失败" : "Unavailable"
        fiveHourExpiryItem.title = "5H -- · \(failureText)"
        weeklyExpiryItem.title = "7D -- · \(failureText)"
        renderCurrentBadge()
    }

    private func updateExpiryItems(for usage: UsageSummary) {
        fiveHourExpiryItem.title = "5H \(usage.fiveHour.remainingPercent)% · \(expiryText(for: usage.fiveHour.resetsAt))"
        weeklyExpiryItem.title = "7D \(usage.weekly.remainingPercent)% · \(expiryText(for: usage.weekly.resetsAt))"
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
            tooltip = "Codex usage: \(lastError.localizedDescription)"
        } else if let lastUsage {
            image = UsageBadgeRenderer.image(for: lastUsage, style: badgeStyle, appearance: button.effectiveAppearance)
            tooltip = lastUsage.tooltip(formatter: dateFormatter)
        } else {
            image = UsageBadgeRenderer.placeholderImage(style: badgeStyle, appearance: button.effectiveAppearance)
            tooltip = "Codex usage: waiting for first refresh"
        }

        statusItem.length = badgeStyle == .quotaAndResetTimes
            ? image.size.width
            : UsageBadgeRenderer.statusItemLength(for: badgeStyle)
        button.title = ""
        button.image = image
        button.toolTip = tooltip
    }
}
