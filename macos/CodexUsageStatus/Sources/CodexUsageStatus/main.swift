import AppKit
import Darwin
import Foundation

private let defaultCodexPath = "/Applications/Codex.app/Contents/Resources/codex"
private let minimumRefreshInterval: TimeInterval = 60
private let defaultRefreshInterval: TimeInterval = 120
private let errorRetryInterval: TimeInterval = 300

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
    private let displayStyleItem = NSMenuItem(title: "Display Style", action: nil, keyEquivalent: "")
    private let displayStyleMenu = NSMenu()
    private let doubleRingItem = NSMenuItem(title: BadgeStyle.doubleRing.menuTitle, action: #selector(selectDoubleRingStyle), keyEquivalent: "")
    private let largeReadoutItem = NSMenuItem(title: BadgeStyle.largeReadout.menuTitle, action: #selector(selectLargeReadoutStyle), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")

    private var timer: Timer?
    private var isRefreshing = false
    private let refreshInterval = configuredRefreshInterval()
    private var badgeStyle = BadgeStyle.load()
    private var lastUsage: UsageSummary?
    private var lastRefreshDate: Date?
    private var lastError: Error?

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "Codex usage: waiting for first refresh"
        }
        renderCurrentBadge()

        refreshItem.target = self
        menu.addItem(refreshItem)

        doubleRingItem.target = self
        largeReadoutItem.target = self
        displayStyleMenu.addItem(doubleRingItem)
        displayStyleMenu.addItem(largeReadoutItem)
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
        Failure retry: \(Int(errorRetryInterval)) seconds
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
                self.scheduleNextRefresh(after: errorRetryInterval)
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
        renderCurrentBadge()
    }

    private func applyError(_ error: Error) {
        lastError = error
        renderCurrentBadge()
    }

    private func renderCurrentBadge() {
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)
        if let button = statusItem.button {
            button.title = ""

            if let lastError {
                button.image = UsageBadgeRenderer.errorImage(style: badgeStyle, appearance: button.effectiveAppearance)
                button.toolTip = "Codex usage: \(lastError.localizedDescription)"
            } else if let lastUsage {
                button.image = UsageBadgeRenderer.image(for: lastUsage, style: badgeStyle, appearance: button.effectiveAppearance)
                button.toolTip = lastUsage.tooltip(formatter: dateFormatter)
            } else {
                button.image = UsageBadgeRenderer.placeholderImage(style: badgeStyle, appearance: button.effectiveAppearance)
                button.toolTip = "Codex usage: waiting for first refresh"
            }
        }
    }
}

private func configuredRefreshInterval() -> TimeInterval {
    let rawValue = ProcessInfo.processInfo.environment["CODEX_USAGE_REFRESH_SECONDS"]
    let requested = rawValue.flatMap(Double.init) ?? defaultRefreshInterval
    return max(minimumRefreshInterval, requested)
}

enum CodexUsageFetcher {
    static func fetch() async throws -> UsageSummary {
        try await Task.detached(priority: .utility) {
            try fetchSync()
        }.value
    }

    static func fetchSync() throws -> UsageSummary {
        let response = try readRateLimits()
        return try UsageSummary(response: response)
    }

    private static func readRateLimits() throws -> RateLimitsResponse {
        let codexPath = ProcessInfo.processInfo.environment["CODEX_BIN"] ?? defaultCodexPath
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            throw FetchError.codexNotFound(codexPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        let responseBox = ResponseBox()
        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            responseBox.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        let requestLines = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_usage_status_menubar","title":"Codex Usage Status","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}"#,
            #"{"method":"initialized"}"#,
            #"{"method":"account/rateLimits/read","id":2}"#
        ].joined(separator: "\n") + "\n"

        standardInput.fileHandleForWriting.write(Data(requestLines.utf8))

        if responseBox.wait(timeout: .now() + 20) == .timedOut {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardInput.fileHandleForWriting.closeFile()
            terminateProcess(process, finished: finished)
            throw FetchError.timeout
        }

        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardInput.fileHandleForWriting.closeFile()
        terminateProcess(process, finished: finished)
        _ = standardError.fileHandleForReading.readDataToEndOfFile()

        switch responseBox.result() {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        case .none:
            throw FetchError.missingRateLimitResponse
        }
    }

    private static func terminateProcess(_ process: Process, finished: DispatchSemaphore) {
        guard process.isRunning else {
            return
        }
        process.terminate()
        if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 1)
        }
    }
}

final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var buffer = ""
    private var storedResult: Result<RateLimitsResponse, Error>?

    func append(_ data: Data) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        if storedResult != nil {
            return
        }

        buffer.append(text)
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)

            do {
                if let response = try Self.parseRateLimitsLine(line) {
                    storedResult = .success(response)
                    semaphore.signal()
                    return
                }
            } catch {
                storedResult = .failure(error)
                semaphore.signal()
                return
            }
        }
    }

    func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        semaphore.wait(timeout: timeout)
    }

    func result() -> Result<RateLimitsResponse, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }

    private static func parseRateLimitsLine(_ line: String) throws -> RateLimitsResponse? {
        guard let lineData = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return nil
        }

        guard stringID(object["id"]) == "2" else {
            return nil
        }

        if object["error"] != nil {
            throw FetchError.appServerError
        }

        guard let result = object["result"] else {
            throw FetchError.invalidOutput
        }

        let resultData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(RateLimitsResponse.self, from: resultData)
    }

    private static func stringID(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

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
    let usedPercent: Int?
    let windowDurationMins: Int?
    let resetsAt: Int?
}

struct UsageSummary: Sendable {
    let planType: String?
    let fiveHour: UsageWindow
    let weekly: UsageWindow

    init(response: RateLimitsResponse) throws {
        let snapshot = response.rateLimitsByLimitId?["codex"]
            ?? response.rateLimits
            ?? response.rateLimitsByLimitId?.values.first

        guard let snapshot else {
            throw FetchError.invalidOutput
        }

        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }.map(UsageWindow.init)
        let fiveHour = windows.first { abs(($0.windowDurationMins ?? 0) - 300) <= 1 } ?? windows.first
        let weekly = windows.first { abs(($0.windowDurationMins ?? 0) - 10080) <= 1 } ?? windows.dropFirst().first

        guard let fiveHour, let weekly else {
            throw FetchError.invalidOutput
        }

        self.planType = snapshot.planType
        self.fiveHour = fiveHour
        self.weekly = weekly
    }

    var menuTitle: String {
        "5h \(fiveHour.remainingPercent)% 7d \(weekly.remainingPercent)%"
    }

    var verboseTitle: String {
        "Codex usage: 5-hour \(fiveHour.remainingPercent)% · weekly \(weekly.remainingPercent)%"
    }

    func tooltip(formatter: DateFormatter) -> String {
        let fiveHourReset = fiveHour.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        let weeklyReset = weekly.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        return "Codex usage\n5-hour remaining: \(fiveHour.remainingPercent)% · resets \(fiveHourReset)\nWeekly remaining: \(weekly.remainingPercent)% · resets \(weeklyReset)"
    }
}

struct UsageWindow: Sendable {
    let remainingPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Date?

    init(_ window: RateLimitWindow) {
        let used = min(100, max(0, window.usedPercent ?? 0))
        remainingPercent = min(100, max(0, 100 - used))
        windowDurationMins = window.windowDurationMins
        resetsAt = window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    func displayText(formatter: DateFormatter) -> String {
        guard let resetsAt else {
            return "\(remainingPercent)% remaining, reset unknown"
        }
        return "\(remainingPercent)% remaining, resets \(formatter.string(from: resetsAt))"
    }
}

enum BadgeStyle: String, CaseIterable {
    case doubleRing
    case largeReadout

    private static let defaultsKey = "BadgeStyle"

    var menuTitle: String {
        switch self {
        case .doubleRing:
            return "Double Ring"
        case .largeReadout:
            return "Large Readout"
        }
    }

    static func load() -> BadgeStyle {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let style = BadgeStyle(rawValue: rawValue) else {
            return .doubleRing
        }
        return style
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

enum UsageBadgeRenderer {
    private static let doubleRingImageSize = NSSize(width: 86, height: 24)
    private static let largeReadoutImageSize = NSSize(width: 86, height: 24)

    static func statusItemLength(for style: BadgeStyle) -> CGFloat {
        switch style {
        case .doubleRing:
            return 90
        case .largeReadout:
            return 90
        }
    }

    static func image(for usage: UsageSummary, style: BadgeStyle, appearance: NSAppearance) -> NSImage {
        render(style: style,
            left: BadgeValue(label: "5H", percent: usage.fiveHour.remainingPercent),
            right: BadgeValue(label: "7D", percent: usage.weekly.remainingPercent),
            appearance: appearance
        )
    }

    static func placeholderImage(style: BadgeStyle, appearance: NSAppearance) -> NSImage {
        render(style: style,
            left: BadgeValue(label: "5H", percent: nil),
            right: BadgeValue(label: "7D", percent: nil),
            appearance: appearance
        )
    }

    static func errorImage(style: BadgeStyle, appearance: NSAppearance) -> NSImage {
        render(style: style,
            left: BadgeValue(label: "5H", percent: nil, overrideText: "?"),
            right: BadgeValue(label: "7D", percent: nil, overrideText: "?"),
            appearance: appearance,
            forcedColor: .systemRed
        )
    }

    private static func render(
        style: BadgeStyle,
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor? = nil
    ) -> NSImage {
        switch style {
        case .doubleRing:
            return renderDoubleRing(left: left, right: right, appearance: appearance, forcedColor: forcedColor)
        case .largeReadout:
            return renderLargeReadout(left: left, right: right, appearance: appearance, forcedColor: forcedColor)
        }
    }

    private static func renderDoubleRing(
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor?
    ) -> NSImage {
        let imageSize = doubleRingImageSize
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        appearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: imageSize)
            NSColor.clear.setFill()
            rect.fill()

            let divider = NSBezierPath()
            divider.appendArc(withCenter: NSPoint(x: 43, y: 12), radius: 1.0, startAngle: 0, endAngle: 360)
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            divider.fill()

            drawLabeledRing(value: left, labelRect: NSRect(x: 1, y: 4.0, width: 11, height: 16), ringCenter: NSPoint(x: 29, y: 12), forcedColor: forcedColor)
            drawLabeledRing(value: right, labelRect: NSRect(x: 50, y: 4.0, width: 11, height: 16), ringCenter: NSPoint(x: 75, y: 12), forcedColor: forcedColor)
        }

        image.isTemplate = false
        return image
    }

    private static func renderLargeReadout(
        left: BadgeValue,
        right: BadgeValue,
        appearance: NSAppearance,
        forcedColor: NSColor?
    ) -> NSImage {
        let imageSize = largeReadoutImageSize
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        appearance.performAsCurrentDrawingAppearance {
            let rect = NSRect(origin: .zero, size: imageSize)
            NSColor.clear.setFill()
            rect.fill()

            let divider = NSBezierPath()
            divider.appendArc(withCenter: NSPoint(x: 43, y: 12), radius: 1.0, startAngle: 0, endAngle: 360)
            NSColor.labelColor.withAlphaComponent(0.28).setFill()
            divider.fill()

            drawReadoutGroup(value: left, labelRect: NSRect(x: 1, y: 4.0, width: 11, height: 16), numberRect: NSRect(x: 15, y: 3.4, width: 25, height: 17), lineRect: NSRect(x: 1, y: 2.4, width: 36, height: 1.5), forcedColor: forcedColor)
            drawReadoutGroup(value: right, labelRect: NSRect(x: 49, y: 4.0, width: 11, height: 16), numberRect: NSRect(x: 61, y: 3.4, width: 25, height: 17), lineRect: NSRect(x: 48, y: 2.4, width: 36, height: 1.5), forcedColor: forcedColor)
        }

        image.isTemplate = false
        return image
    }

    private static func drawLabeledRing(
        value: BadgeValue,
        labelRect: NSRect,
        ringCenter: NSPoint,
        forcedColor: NSColor?
    ) {
        drawSideLabel(value.label, in: labelRect)
        drawRing(value: value, center: ringCenter, forcedColor: forcedColor)
    }

    private static func drawRing(value: BadgeValue, center: NSPoint, forcedColor: NSColor?) {
        let radius: CGFloat = 9.7
        let lineWidth: CGFloat = 2.25
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        NSColor.labelColor.withAlphaComponent(0.20).setStroke()
        track.stroke()

        if let percent = value.percent {
            let progress = max(0, min(100, percent))
            let ring = NSBezierPath()
            ring.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - CGFloat(progress) * 3.6,
                clockwise: true
            )
            ring.lineWidth = lineWidth
            ring.lineCapStyle = .round
            (forcedColor ?? color(for: progress)).withAlphaComponent(0.92).setStroke()
            ring.stroke()
        }

        drawText(value.centerText, center: center, yOffset: -5.5, fontSize: value.centerText.count >= 3 ? 7.4 : 9.0, weight: .bold, alpha: 0.98)
    }

    private static func drawReadoutGroup(
        value: BadgeValue,
        labelRect: NSRect,
        numberRect: NSRect,
        lineRect: NSRect,
        forcedColor: NSColor?
    ) {
        let percent = value.percent.map { max(0, min(100, $0)) }
        let accent = forcedColor ?? percent.map(color(for:)) ?? NSColor.labelColor.withAlphaComponent(0.26)
        let emphasisAlpha: CGFloat = (percent ?? 100) < 20 ? 1.0 : 0.96

        drawStackedLabel(value.label, in: labelRect, alpha: 0.62)
        drawString(value.centerText, in: numberRect, fontSize: value.centerText.count >= 3 ? 11.6 : 13.2, weight: .bold, alpha: emphasisAlpha, alignment: .left)

        let track = NSBezierPath(roundedRect: lineRect, xRadius: 0.7, yRadius: 0.7)
        NSColor.labelColor.withAlphaComponent(0.14).setFill()
        track.fill()

        if let percent {
            let fillWidth = max(1.2, lineRect.width * CGFloat(percent) / 100)
            let fillRect = NSRect(x: lineRect.minX, y: lineRect.minY, width: fillWidth, height: lineRect.height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 0.7, yRadius: 0.7)
            accent.withAlphaComponent(percent < 20 ? 0.95 : 0.72).setFill()
            fillPath.fill()
        }
    }

    private static func drawText(
        _ text: String,
        center: NSPoint,
        yOffset: CGFloat,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat
    ) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha),
            .paragraphStyle: centeredParagraphStyle,
        ]
        let height = fontSize + 2
        let rect = NSRect(x: center.x - 10, y: center.y + yOffset, width: 20, height: height)
        text.draw(in: rect, withAttributes: attributes)
    }

    private static func drawSideLabel(_ text: String, in rect: NSRect) {
        drawStackedLabel(text, in: rect, alpha: 0.78)
    }

    private static func drawStackedLabel(_ text: String, in rect: NSRect, alpha: CGFloat) {
        let lines: [String]
        let normalized = text.uppercased()
        if normalized.count == 2 {
            lines = normalized.map(String.init)
        } else {
            lines = [normalized]
        }

        let fontSize: CGFloat = lines.count > 1 ? 7.4 : 10.0
        let lineHeight: CGFloat = lines.count > 1 ? 7.5 : 10.8
        let totalHeight = CGFloat(lines.count) * lineHeight
        let startY = rect.midY + totalHeight / 2 - lineHeight

        for (index, line) in lines.enumerated() {
            let lineRect = NSRect(
                x: rect.minX,
                y: startY - CGFloat(index) * lineHeight,
                width: rect.width,
                height: lineHeight
            )
            drawString(line, in: lineRect, fontSize: fontSize, weight: .bold, alpha: alpha, alignment: .center)
        }
    }

    private static func drawString(
        _ text: String,
        in rect: NSRect,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        alpha: CGFloat,
        alignment: NSTextAlignment
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha),
            .paragraphStyle: style,
        ]
        text.draw(in: rect, withAttributes: attributes)
    }

    private static var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byClipping
        return style
    }

    private static func color(for percent: Int) -> NSColor {
        switch percent {
        case 50...100:
            return .systemGreen
        case 20..<50:
            return .systemOrange
        default:
            return .systemRed
        }
    }
}

struct BadgeValue {
    let label: String
    let percent: Int?
    let overrideText: String?

    init(label: String, percent: Int?, overrideText: String? = nil) {
        self.label = label
        self.percent = percent
        self.overrideText = overrideText
    }

    var centerText: String {
        if let overrideText {
            return overrideText
        }
        guard let percent else {
            return "--"
        }
        return "\(percent)"
    }
}

enum FetchError: LocalizedError {
    case codexNotFound(String)
    case timeout
    case appServerExited(Int)
    case appServerError
    case invalidOutput
    case missingRateLimitResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound(let path):
            return "Codex binary not found at \(path)"
        case .timeout:
            return "Codex app-server did not respond within 20 seconds"
        case .appServerExited(let status):
            return "Codex app-server exited with status \(status)"
        case .appServerError:
            return "Codex app-server returned an error"
        case .invalidOutput:
            return "Codex app-server returned unexpected usage data"
        case .missingRateLimitResponse:
            return "Codex app-server did not return usage data"
        }
    }
}

if CommandLine.arguments.contains("--once") {
    do {
        let usage = try CodexUsageFetcher.fetchSync()
        print(usage.menuTitle)
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
