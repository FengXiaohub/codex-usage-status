import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let codexFiveHourItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let codexWeeklyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let codexSeparator = NSMenuItem.separator()
    private let geminiFiveHourItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let geminiWeeklyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let geminiSeparator = NSMenuItem.separator()
    private let claudeGptFiveHourItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let claudeGptWeeklyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let claudeGptSeparator = NSMenuItem.separator()

    private let tokenHeaderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let tokenTotalItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var tokenProviderItems: [TokenProvider: NSMenuItem] = [:]

    private let refreshItem = NSMenuItem(title: "", action: #selector(refreshFromMenu), keyEquivalent: "r")
    private let displayStyleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let displayStyleMenu = NSMenu()
    private let doubleRingItem = NSMenuItem(title: "", action: #selector(selectDoubleRingStyle), keyEquivalent: "")
    private let largeReadoutItem = NSMenuItem(title: "", action: #selector(selectLargeReadoutStyle), keyEquivalent: "")
    private let quotaAndResetTimesItem = NSMenuItem(title: "", action: #selector(selectQuotaAndResetTimesStyle), keyEquivalent: "")
    private let visibleQuotasItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let visibleQuotasMenu = NSMenu()
    private let toggleCodexQuotaItem = NSMenuItem(title: "[C] Codex", action: #selector(toggleCodexQuota), keyEquivalent: "")
    private let toggleGeminiQuotaItem = NSMenuItem(title: "[G] Gemini", action: #selector(toggleGeminiQuota), keyEquivalent: "")
    private let toggleClaudeGptQuotaItem = NSMenuItem(title: "[A] Claude & GPT", action: #selector(toggleClaudeGptQuota), keyEquivalent: "")
    private let lowQuotaNotifyItem = NSMenuItem(title: "", action: #selector(toggleLowQuotaNotifications), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "", action: #selector(showSettings), keyEquivalent: ",")

    private var timer: Timer?
    private var isRefreshing = false
    private var isScreenAsleep = false
    private var refreshStartedAt: Date?
    private var refreshGeneration = 0
    private var isScanningTokens = false
    private var lastTokenReport: TokenUsageReport?
    private var lastTokenScanDate: Date?
    private let refreshInterval = configuredRefreshInterval()
    private var badgeStyle = BadgeStyle.load()
    private var quotaVisibility = QuotaVisibility.load()
    private var lowQuotaAlerts = LowQuotaAlertTracker.load()
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
    private var lastRenderedAppearanceName: NSAppearance.Name?

    private static func resolvedAppearanceName(for appearance: NSAppearance) -> NSAppearance.Name {
        appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]) ?? appearance.name
    }

    private var usesChinese: Bool {
        Locale.current.language.languageCode?.identifier == "zh"
    }

    private var idleRefreshTitle: String {
        usesChinese ? "立即刷新" : "Refresh"
    }

    private var activeRefreshTitle: String {
        usesChinese ? "正在刷新…" : "Refreshing..."
    }

    private var copyRowHint: String {
        usesChinese ? "点击复制该行" : "Click to copy line"
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
        menu.autoenablesItems = false

        let loadingText = usesChinese ? "读取中" : "Loading"
        for item in [
            codexFiveHourItem, codexWeeklyItem,
            geminiFiveHourItem, geminiWeeklyItem,
            claudeGptFiveHourItem, claudeGptWeeklyItem,
            tokenHeaderItem, tokenTotalItem,
        ] {
            makeCopyableInfoItem(item)
        }
        codexFiveHourItem.title = "[C] Codex 5H -- · \(loadingText)"
        codexWeeklyItem.title = "[C] Codex 7D -- · \(loadingText)"
        geminiFiveHourItem.title = "[G] Gemini 5H -- · \(loadingText)"
        geminiWeeklyItem.title = "[G] Gemini 7D -- · \(loadingText)"
        claudeGptFiveHourItem.title = "[A] Claude & GPT 5H -- · \(loadingText)"
        claudeGptWeeklyItem.title = "[A] Claude & GPT 7D -- · \(loadingText)"

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = usesChinese ? "Codex & Antigravity：等待首次刷新" : "Codex & Antigravity usage: waiting for first refresh"
        }
        renderCurrentBadge()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let currentAppearance = self.statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
                let resolvedName = Self.resolvedAppearanceName(for: currentAppearance)
                guard resolvedName != self.lastRenderedAppearanceName else {
                    return
                }
                self.renderCurrentBadge()
            }
        }

        menu.addItem(codexFiveHourItem)
        menu.addItem(codexWeeklyItem)
        menu.addItem(codexSeparator)
        menu.addItem(geminiFiveHourItem)
        menu.addItem(geminiWeeklyItem)
        menu.addItem(geminiSeparator)
        menu.addItem(claudeGptFiveHourItem)
        menu.addItem(claudeGptWeeklyItem)
        menu.addItem(claudeGptSeparator)
        applyQuotaMenuVisibility()

        setMenuText(
            tokenHeaderItem,
            usesChinese
                ? "Token 用量 · 今日 / 近 \(AppConfig.tokenWindowDays) 天"
                : "Token usage · Today / \(AppConfig.tokenWindowDays) days",
            emphasized: true
        )
        tokenHeaderItem.toolTip = usesChinese
            ? "总量含缓存命中的输入（只读本机日志，不上传）。点击可复制完整 Token 汇总。"
            : "Totals include cached input (local logs only, never uploaded). Click to copy full token summary."
        menu.addItem(tokenHeaderItem)
        for provider in TokenProvider.allCases {
            let item = NSMenuItem(title: "\(provider.menuPrefix) -- · \(loadingText)", action: nil, keyEquivalent: "")
            item.isEnabled = true
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            submenu.addItem(infoItem(loadingText))
            item.submenu = submenu
            tokenProviderItems[provider] = item
            menu.addItem(item)
        }
        setMenuText(
            tokenTotalItem,
            usesChinese ? "合计 -- · \(loadingText)" : "Total -- · \(loadingText)",
            emphasized: true
        )
        menu.addItem(tokenTotalItem)
        menu.addItem(.separator())

        refreshItem.title = idleRefreshTitle
        refreshItem.target = self
        menu.addItem(refreshItem)

        displayStyleItem.title = usesChinese ? "显示样式" : "Display Style"
        doubleRingItem.title = BadgeStyle.doubleRing.menuTitle(chinese: usesChinese)
        largeReadoutItem.title = BadgeStyle.largeReadout.menuTitle(chinese: usesChinese)
        quotaAndResetTimesItem.title = BadgeStyle.quotaAndResetTimes.menuTitle(chinese: usesChinese)
        doubleRingItem.target = self
        largeReadoutItem.target = self
        quotaAndResetTimesItem.target = self
        displayStyleMenu.addItem(quotaAndResetTimesItem)
        displayStyleMenu.addItem(doubleRingItem)
        displayStyleMenu.addItem(largeReadoutItem)
        displayStyleItem.submenu = displayStyleMenu
        menu.addItem(displayStyleItem)
        updateStyleMenuState()

        visibleQuotasItem.title = usesChinese ? "显示额度" : "Visible Quotas"
        visibleQuotasMenu.autoenablesItems = false
        toggleCodexQuotaItem.target = self
        toggleGeminiQuotaItem.target = self
        toggleClaudeGptQuotaItem.target = self
        visibleQuotasMenu.addItem(toggleCodexQuotaItem)
        visibleQuotasMenu.addItem(toggleGeminiQuotaItem)
        visibleQuotasMenu.addItem(toggleClaudeGptQuotaItem)
        visibleQuotasItem.submenu = visibleQuotasMenu
        menu.addItem(visibleQuotasItem)
        updateVisibilityMenuState()

        lowQuotaNotifyItem.title = usesChinese ? "低额度通知提醒" : "Low-Quota Notifications"
        lowQuotaNotifyItem.target = self
        menu.addItem(lowQuotaNotifyItem)
        updateLowQuotaNotifyMenuState()

        launchAtLoginItem.title = usesChinese ? "开机自启" : "Launch at Login"
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        updateLaunchAtLoginMenuState()

        settingsItem.title = usesChinese ? "设置与状态…" : "Settings..."
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: usesChinese ? "退出" : "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
        lastClientSignature = Self.currentClientSignature()

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(workspaceDidWakeOrActivate), name: NSWorkspace.didWakeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(workspaceDidWakeOrActivate), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(screensOrSessionDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(screensOrSessionDidSleep), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(screensOrSessionDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(screensOrSessionDidWake), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        // Warm token cache once at launch; background quota timers never scan disk logs again.
        refreshTokens(force: true)
        refresh(scanTokens: false)
    }

    @objc private func screensOrSessionDidSleep(_ notification: Notification) {
        isScreenAsleep = true
        timer?.invalidate()
        timer = nil
    }

    @objc private func screensOrSessionDidWake(_ notification: Notification) {
        guard isScreenAsleep else { return }
        isScreenAsleep = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func workspaceDidWakeOrActivate(_ notification: Notification) {
        if notification.name == NSWorkspace.didWakeNotification {
            isScreenAsleep = false
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConfig.wakeRefreshDelay) { [weak self] in
                guard let self else { return }
                self.lastClientSignature = Self.currentClientSignature()
                self.refresh()
            }
            return
        }

        guard !isScreenAsleep else { return }
        let newSignature = Self.currentClientSignature()
        if newSignature != lastClientSignature {
            lastClientSignature = newSignature
            refresh()
            return
        }
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let name = app.localizedName?.lowercased(),
           name.contains("antigravity") || name.contains("chatgpt") || name.contains("codex") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.refresh()
            }
            if name.contains("antigravity") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) { [weak self] in
                    self?.refresh()
                }
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
        refresh(forceRestart: true, scanTokens: true)
    }

    @objc private func timerDidFire() {
        refresh(scanTokens: false)
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

    @objc private func toggleCodexQuota() {
        toggleQuotaVisibility(for: .codex)
    }

    @objc private func toggleGeminiQuota() {
        toggleQuotaVisibility(for: .gemini)
    }

    @objc private func toggleClaudeGptQuota() {
        toggleQuotaVisibility(for: .claudeGpt)
    }

    @objc private func toggleLowQuotaNotifications() {
        lowQuotaAlerts.isEnabled.toggle()
        lowQuotaAlerts.save()
        updateLowQuotaNotifyMenuState()
        if lowQuotaAlerts.isEnabled {
            LowQuotaNotifier.requestAuthorizationIfNeeded()
        }
    }

    private func updateLowQuotaNotifyMenuState() {
        lowQuotaNotifyItem.state = lowQuotaAlerts.isEnabled ? .on : .off
        lowQuotaNotifyItem.toolTip = usesChinese
            ? "当可见额度首次跌破 \(AppConfig.lowQuotaRedThresholdPercent)% 时发送系统通知（每个重置周期最多提醒一次）"
            : "Send a macOS notification when a visible quota drops below \(AppConfig.lowQuotaRedThresholdPercent)% (at most once per reset cycle)"
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = usesChinese ? "无法更改开机自启设置" : "Unable to Update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: usesChinese ? "好" : "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        updateLaunchAtLoginMenuState()
    }

    private func updateLaunchAtLoginMenuState() {
        let status = SMAppService.mainApp.status
        launchAtLoginItem.state = (status == .enabled) ? .on : .off
        if status == .requiresApproval {
            launchAtLoginItem.toolTip = usesChinese
                ? "请在「系统设置 > 通用 > 登录项」中允许 Codex Usage Status"
                : "Allow Codex Usage Status in System Settings > General > Login Items"
        } else {
            launchAtLoginItem.toolTip = nil
        }
    }

    @objc private func showSettings() {
        let neverText = usesChinese ? "尚未执行" : "Never"
        let status: String
        if let lastError {
            status = usesChinese
                ? "上次刷新失败：\(lastError.localizedDescription)"
                : "Last refresh failed: \(lastError.localizedDescription)"
        } else if let lastUsage {
            status = lastUsage.verboseTitle(for: quotaVisibility)
        } else {
            status = usesChinese ? "等待首次刷新" : "Waiting for first refresh"
        }

        let lastRefresh = lastRefreshDate.map { dateFormatter.string(from: $0) } ?? neverText
        let lastTokenScan = lastTokenScanDate.map { dateFormatter.string(from: $0) } ?? neverText
        let visibleList = quotaVisibility.visibleProviders.map(\.menuPrefix).joined(separator: ", ")
        let loginState = (SMAppService.mainApp.status == .enabled)
            ? (usesChinese ? "已开启" : "Enabled")
            : (usesChinese ? "未开启" : "Disabled")
        let notifyState = lowQuotaAlerts.isEnabled
            ? (usesChinese ? "已开启（每重置周期一次）" : "Enabled (once per cycle)")
            : (usesChinese ? "已关闭" : "Disabled")

        let message: String
        if usesChinese {
            message = """
            \(status)

            显示样式：\(badgeStyle.menuTitle(chinese: true))
            显示额度：\(visibleList)
            低额度提醒：< \(AppConfig.lowQuotaRedThresholdPercent)% 红底白字胶囊 · 通知\(notifyState)
            开机自启：\(loginState)
            刷新间隔：\(Int(refreshInterval)) 秒（息屏自动暂停，失败重试 \(Int(AppConfig.errorRetryInterval)) 秒）
            上次刷新：\(lastRefresh)
            Token 扫描：\(lastTokenScan)（仅点开菜单/手动刷新时增量扫描）
            当前版本：\(AppConfig.appVersion)
            """
        } else {
            message = """
            \(status)

            Display style: \(badgeStyle.menuTitle(chinese: false))
            Visible quotas: \(visibleList)
            Low-quota alert: < \(AppConfig.lowQuotaRedThresholdPercent)% red capsule · notifications \(notifyState)
            Launch at login: \(loginState)
            Refresh interval: \(Int(refreshInterval))s (paused while screen sleeps; retry \(Int(AppConfig.errorRetryInterval))s)
            Last refresh: \(lastRefresh)
            Last token scan: \(lastTokenScan) (on-demand incremental scan)
            Version: \(AppConfig.appVersion)
            """
        }

        let alert = NSAlert()
        alert.messageText = "Codex & Antigravity Usage Status"
        alert.informativeText = message
        alert.addButton(withTitle: usesChinese ? "好" : "OK")
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

    private func toggleQuotaVisibility(for provider: TokenProvider) {
        let wasVisible = quotaVisibility.isVisible(provider)
        guard quotaVisibility.toggle(provider) else {
            return
        }
        quotaVisibility.save()
        updateVisibilityMenuState()

        if lastError != nil, let lastUsage, lastUsage.hasAnyUsage(for: quotaVisibility) {
            lastError = nil
        }

        if let lastUsage {
            updateExpiryItems(for: lastUsage)
        } else {
            applyQuotaMenuVisibility()
        }
        renderCurrentBadge()

        if !wasVisible {
            let needsFetch: Bool
            switch provider {
            case .codex:
                needsFetch = lastUsage?.codex == nil
            case .gemini:
                needsFetch = lastUsage?.gemini == nil
            case .claudeGpt:
                needsFetch = lastUsage?.claudeGpt == nil
            }
            if needsFetch {
                refresh(forceRestart: true)
            }
        }
    }

    private func updateVisibilityMenuState() {
        let keepOneTip = usesChinese ? "至少保留一项在状态栏显示" : "Keep at least one quota visible in the menu bar"
        let items: [(TokenProvider, NSMenuItem)] = [
            (.codex, toggleCodexQuotaItem),
            (.gemini, toggleGeminiQuotaItem),
            (.claudeGpt, toggleClaudeGptQuotaItem),
        ]
        for (provider, item) in items {
            let visible = quotaVisibility.isVisible(provider)
            let canToggle = quotaVisibility.canHide(provider)
            item.state = visible ? .on : .off
            item.isEnabled = canToggle
            item.toolTip = canToggle ? nil : keepOneTip
        }
    }

    private func applyQuotaMenuVisibility() {
        let showCodex = quotaVisibility.isVisible(.codex)
        let codexHasFiveHour = (lastError == nil && lastUsage != nil)
            ? (lastUsage?.codex == nil || lastUsage?.codex?.fiveHour != nil)
            : true
        codexFiveHourItem.isHidden = !showCodex || !codexHasFiveHour
        codexWeeklyItem.isHidden = !showCodex
        codexSeparator.isHidden = !showCodex

        let showGemini = quotaVisibility.isVisible(.gemini)
        let geminiHasFiveHour = (lastError == nil && lastUsage != nil)
            ? (lastUsage?.gemini == nil || lastUsage?.gemini?.fiveHour != nil)
            : true
        geminiFiveHourItem.isHidden = !showGemini || !geminiHasFiveHour
        geminiWeeklyItem.isHidden = !showGemini
        geminiSeparator.isHidden = !showGemini

        let showClaudeGpt = quotaVisibility.isVisible(.claudeGpt)
        let claudeHasFiveHour = (lastError == nil && lastUsage != nil)
            ? (lastUsage?.claudeGpt == nil || lastUsage?.claudeGpt?.fiveHour != nil)
            : true
        claudeGptFiveHourItem.isHidden = !showClaudeGpt || !claudeHasFiveHour
        claudeGptWeeklyItem.isHidden = !showClaudeGpt
        claudeGptSeparator.isHidden = !showClaudeGpt
    }

    private func refresh(forceRestart: Bool = false, scanTokens: Bool = false) {
        if isRefreshing && !forceRestart {
            guard let started = refreshStartedAt,
                  Date().timeIntervalSince(started) >= AppConfig.refreshWatchdogInterval else {
                return
            }
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        let visibilitySnapshot = quotaVisibility
        isRefreshing = true
        refreshStartedAt = Date()
        refreshItem.isEnabled = false
        refreshItem.title = activeRefreshTitle
        scheduleNextRefresh(after: AppConfig.refreshWatchdogInterval)
        if scanTokens {
            refreshTokens(force: true)
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let usage = try await CodexUsageFetcher.fetchCombined(visibility: visibilitySnapshot)
                guard generation == self.refreshGeneration else { return }
                self.finishRefresh()
                let hadTransientFailure = self.applyUsage(usage)
                self.scheduleNextRefresh(after: hadTransientFailure ? AppConfig.transientRetryInterval : self.refreshInterval)
            } catch {
                guard generation == self.refreshGeneration else { return }
                self.finishRefresh()
                let retainedStale = self.applyError(error)
                self.scheduleNextRefresh(after: retainedStale ? AppConfig.transientRetryInterval : AppConfig.errorRetryInterval)
            }
        }
    }

    private func finishRefresh() {
        isRefreshing = false
        refreshStartedAt = nil
        refreshItem.isEnabled = true
        refreshItem.title = idleRefreshTitle
    }

    // MARK: - Token usage

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        updateLaunchAtLoginMenuState()
        refreshTokens(force: false)
    }

    private func refreshTokens(force: Bool) {
        guard !isScanningTokens else { return }
        if !force, let last = lastTokenScanDate, Date().timeIntervalSince(last) < AppConfig.tokenRescanThrottle {
            return
        }
        isScanningTokens = true
        Task { [weak self] in
            let report = await Task.detached(priority: .utility) {
                TokenUsageScanner.shared.scan()
            }.value
            guard let self else { return }
            self.isScanningTokens = false
            self.lastTokenScanDate = Date()
            self.lastTokenReport = report
            self.updateTokenItems(report)
        }
    }

    private func updateTokenItems(_ report: TokenUsageReport) {
        let todayLabel = usesChinese ? "今日" : "Today"
        let windowLabel = usesChinese ? "近\(report.windowDays)天" : "\(report.windowDays)d"

        for provider in TokenProvider.allCases {
            guard let item = tokenProviderItems[provider], let submenu = item.submenu else { continue }
            let today = report.total(provider: provider, range: .today)
            let window = report.total(provider: provider, range: .lastDays)
            item.title = "\(provider.menuPrefix) \(todayLabel) \(TokenFormat.compact(today.total)) · \(windowLabel) \(TokenFormat.compact(window.total))"

            submenu.removeAllItems()
            submenu.addItem(infoItem("\(todayLabel)：\(TokenFormat.breakdown(today, chinese: usesChinese))"))
            submenu.addItem(infoItem("\(windowLabel)：\(TokenFormat.breakdown(window, chinese: usesChinese))"))

            let models = report.prioritizedModels(provider: provider)
            if !models.isEmpty {
                submenu.addItem(.separator())
                let headerTitle = usesChinese
                    ? "按模型（今日优先 · \(windowLabel)）"
                    : "By model (today first · \(windowLabel))"
                submenu.addItem(infoItem(headerTitle, emphasized: true))
                for entry in models.prefix(15) {
                    let displayModel = TokenFormat.displayModelName(entry.model, chinese: usesChinese)
                    let row = infoItem("\(displayModel)  \(todayLabel) \(TokenFormat.compact(entry.today.total)) · \(windowLabel) \(TokenFormat.compact(entry.window.total))")
                    row.toolTip = "\(TokenFormat.breakdown(entry.window, chinese: usesChinese)) · \(copyRowHint)"
                    row.indentationLevel = 1
                    submenu.addItem(row)
                }
            }
        }

        let today = report.total(provider: nil, range: .today)
        let window = report.total(provider: nil, range: .lastDays)
        setMenuText(
            tokenTotalItem,
            "\(usesChinese ? "合计" : "Total") \(todayLabel) \(TokenFormat.compact(today.total)) · \(windowLabel) \(TokenFormat.compact(window.total))",
            emphasized: true
        )
    }

    @objc private func copyInfoItemAction(_ sender: NSMenuItem) {
        let textToCopy: String
        if sender === tokenHeaderItem, let summary = lastTokenReport?.textSummary {
            textToCopy = summary
        } else {
            textToCopy = sender.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !textToCopy.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textToCopy, forType: .string)
    }

    private func makeCopyableInfoItem(_ item: NSMenuItem) {
        item.target = self
        item.action = #selector(copyInfoItemAction(_:))
        item.isEnabled = true
        if item.toolTip == nil {
            item.toolTip = copyRowHint
        }
    }

    private func setMenuText(_ item: NSMenuItem, _ text: String, emphasized: Bool) {
        item.title = text
        if emphasized {
            let pointSize = NSFont.menuFont(ofSize: 0).pointSize
            let font = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .semibold)
            item.attributedTitle = NSAttributedString(string: text, attributes: [.font: font])
        } else {
            item.attributedTitle = nil
        }
    }

    private func infoItem(_ title: String, emphasized: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        makeCopyableInfoItem(item)
        setMenuText(item, title, emphasized: emphasized)
        return item
    }

    private func scheduleNextRefresh(after seconds: TimeInterval) {
        timer?.invalidate()
        guard !isScreenAsleep else {
            timer = nil
            return
        }
        let nextTimer = Timer.scheduledTimer(timeInterval: seconds, target: self, selector: #selector(timerDidFire), userInfo: nil, repeats: false)
        nextTimer.tolerance = min(15, max(1, seconds * 0.1))
        timer = nextTimer
    }

    @discardableResult
    private func applyUsage(_ usage: CombinedUsageSummary) -> Bool {
        let now = Date()
        var resolvedCodex = usage.codex
        var resolvedCodexError = usage.codexError
        var hadTransientFailure = false

        if let codex = usage.codex {
            lastValidCodex = codex
            consecutiveCodexFailures = 0
        } else if !quotaVisibility.includesCodex {
            resolvedCodex = lastValidCodex?.rollingOverExpiredWindows(at: now)
            resolvedCodexError = nil
            consecutiveCodexFailures = 0
        } else {
            consecutiveCodexFailures += 1
            if consecutiveCodexFailures <= AppConfig.maxStaleFailuresBeforeError, let cached = lastValidCodex {
                resolvedCodex = cached.rollingOverExpiredWindows(at: now)
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
        } else if usage.antigravityError == nil {
            resolvedGemini = lastValidGemini?.rollingOverExpiredWindows(at: now)
            resolvedClaudeGpt = lastValidClaudeGpt?.rollingOverExpiredWindows(at: now)
            consecutiveAntigravityFailures = 0
        } else {
            consecutiveAntigravityFailures += 1
            if consecutiveAntigravityFailures <= AppConfig.maxStaleFailuresBeforeError,
               (lastValidGemini != nil || lastValidClaudeGpt != nil) {
                resolvedGemini = lastValidGemini?.rollingOverExpiredWindows(at: now)
                resolvedClaudeGpt = lastValidClaudeGpt?.rollingOverExpiredWindows(at: now)
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
        lastRefreshDate = now
        lastError = nil
        updateExpiryItems(for: merged)
        renderCurrentBadge()

        let triggeredAlerts = lowQuotaAlerts.evaluate(usage: merged, visibility: quotaVisibility, now: now)
        if !triggeredAlerts.isEmpty {
            lowQuotaAlerts.save()
            LowQuotaNotifier.deliver(triggeredAlerts, chinese: usesChinese) { [weak self] date in
                self?.expiryText(for: date) ?? "--"
            }
        }
        return hadTransientFailure
    }

    @discardableResult
    private func applyError(_ error: Error) -> Bool {
        if quotaVisibility.includesCodex {
            consecutiveCodexFailures += 1
        }
        if quotaVisibility.includesAntigravity {
            consecutiveAntigravityFailures += 1
        }

        let codexWithinGrace = !quotaVisibility.includesCodex || consecutiveCodexFailures <= AppConfig.maxStaleFailuresBeforeError
        let agyWithinGrace = !quotaVisibility.includesAntigravity || consecutiveAntigravityFailures <= AppConfig.maxStaleFailuresBeforeError
        if codexWithinGrace,
           agyWithinGrace,
           let cachedUsage = lastUsage,
           cachedUsage.hasAnyUsage(for: quotaVisibility) {
            return true
        }

        lastError = error
        let failureText = usesChinese ? "读取失败" : "Unavailable"
        let codexLongLabel = lastValidCodex?.weekly.shortLabel ?? "7D"
        codexFiveHourItem.title = "[C] Codex 5H -- · \(failureText)"
        codexWeeklyItem.title = "[C] Codex \(codexLongLabel) -- · \(failureText)"
        geminiFiveHourItem.title = "[G] Gemini 5H -- · \(failureText)"
        geminiWeeklyItem.title = "[G] Gemini 7D -- · \(failureText)"
        claudeGptFiveHourItem.title = "[A] Claude & GPT 5H -- · \(failureText)"
        claudeGptWeeklyItem.title = "[A] Claude & GPT 7D -- · \(failureText)"
        applyQuotaMenuVisibility()
        renderCurrentBadge()
        return false
    }

    private func updateExpiryItems(for usage: CombinedUsageSummary) {
        updateGroupMenuItems(
            prefix: "[C] Codex",
            summary: usage.codex,
            errorDescription: usage.codexError,
            fiveHourItem: codexFiveHourItem,
            weeklyItem: codexWeeklyItem
        )
        updateGroupMenuItems(
            prefix: "[G] Gemini",
            summary: usage.gemini,
            errorDescription: usage.antigravityError,
            fiveHourItem: geminiFiveHourItem,
            weeklyItem: geminiWeeklyItem
        )
        updateGroupMenuItems(
            prefix: "[A] Claude & GPT",
            summary: usage.claudeGpt,
            errorDescription: usage.antigravityError,
            fiveHourItem: claudeGptFiveHourItem,
            weeklyItem: claudeGptWeeklyItem
        )
        applyQuotaMenuVisibility()
    }

    private func updateGroupMenuItems(
        prefix: String,
        summary: UsageSummary?,
        errorDescription: String?,
        fiveHourItem: NSMenuItem,
        weeklyItem: NSMenuItem
    ) {
        guard let summary else {
            let statusText: String
            if errorDescription != nil {
                statusText = usesChinese ? "读取失败" : "Unavailable"
            } else {
                statusText = usesChinese ? "未运行" : "Not running"
            }
            fiveHourItem.title = "\(prefix) 5H -- · \(statusText)"
            weeklyItem.title = "\(prefix) 7D -- · \(statusText)"
            return
        }

        if let fiveHour = summary.fiveHour {
            fiveHourItem.title = "\(prefix) 5H \(fiveHour.remainingPercent)% · \(expiryText(for: fiveHour.resetsAt))"
        }
        weeklyItem.title = "\(prefix) \(summary.weekly.shortLabel) \(summary.weekly.remainingPercent)% · \(expiryText(for: summary.weekly.resetsAt))"
    }

    private func expiryText(for date: Date?) -> String {
        guard let date else {
            return usesChinese ? "未知" : "Unknown"
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
            image = UsageBadgeRenderer.errorImage(
                style: badgeStyle,
                visibility: quotaVisibility,
                appearance: button.effectiveAppearance
            )
            tooltip = "Codex & Antigravity usage: \(lastError.localizedDescription)"
        } else if let lastUsage {
            image = UsageBadgeRenderer.image(
                for: lastUsage,
                style: badgeStyle,
                visibility: quotaVisibility,
                appearance: button.effectiveAppearance
            )
            tooltip = lastUsage.tooltip(formatter: dateFormatter, visibility: quotaVisibility)
        } else {
            image = UsageBadgeRenderer.placeholderImage(
                style: badgeStyle,
                visibility: quotaVisibility,
                appearance: button.effectiveAppearance
            )
            tooltip = usesChinese ? "Codex & Antigravity：等待首次刷新" : "Codex & Antigravity usage: waiting for first refresh"
        }

        statusItem.length = image.size.width
        button.title = ""
        button.image = image
        button.toolTip = tooltip
        lastRenderedAppearanceName = Self.resolvedAppearanceName(for: button.effectiveAppearance)
    }
}
