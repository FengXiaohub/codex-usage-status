import AppKit
import Foundation

private let defaultCodexPath = "/Applications/Codex.app/Contents/Resources/codex"
private let refreshInterval: TimeInterval = 60

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let summaryItem = NSMenuItem(title: "Codex usage", action: nil, keyEquivalent: "")
    private let fiveHourItem = NSMenuItem(title: "5-hour: --", action: nil, keyEquivalent: "")
    private let weeklyItem = NSMenuItem(title: "Weekly: --", action: nil, keyEquivalent: "")
    private let lastRefreshItem = NSMenuItem(title: "Last refresh: --", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")

    private var timer: Timer?
    private var isRefreshing = false

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.title = "5h -- 7d --"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "Codex usage")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.toolTip = "Codex usage: waiting for first refresh"
        }

        for item in [summaryItem, fiveHourItem, weeklyItem, lastRefreshItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refresh()
        timer = Timer.scheduledTimer(timeInterval: refreshInterval, target: self, selector: #selector(timerDidFire), userInfo: nil, repeats: true)
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
            } catch {
                self.isRefreshing = false
                self.refreshItem.isEnabled = true
                self.refreshItem.title = "Refresh"
                self.applyError(error)
            }
        }
    }

    private func applyUsage(_ usage: UsageSummary) {
        if let button = statusItem.button {
            button.title = usage.menuTitle
            button.toolTip = usage.tooltip(formatter: dateFormatter)
        }
        summaryItem.title = usage.planType.map { "\(usage.verboseTitle) (\($0))" } ?? usage.verboseTitle
        fiveHourItem.title = "5-hour: \(usage.fiveHour.displayText(formatter: dateFormatter))"
        weeklyItem.title = "Weekly: \(usage.weekly.displayText(formatter: dateFormatter))"
        lastRefreshItem.title = "Last refresh: \(dateFormatter.string(from: Date()))"
    }

    private func applyError(_ error: Error) {
        if let button = statusItem.button {
            button.title = "5h ? 7d ?"
            button.toolTip = "Codex usage: \(error.localizedDescription)"
        }
        summaryItem.title = "Unable to read Codex usage"
        fiveHourItem.title = "5-hour: --"
        weeklyItem.title = "Weekly: --"
        lastRefreshItem.title = error.localizedDescription
    }
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

        try process.run()

        let requestLines = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_usage_status_menubar","title":"Codex Usage Status","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}"#,
            #"{"method":"initialized"}"#,
            #"{"method":"account/rateLimits/read","id":2}"#
        ].joined(separator: "\n") + "\n"

        standardInput.fileHandleForWriting.write(Data(requestLines.utf8))

        if responseBox.wait(timeout: .now() + 20) == .timedOut {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            process.terminate()
            throw FetchError.timeout
        }

        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardInput.fileHandleForWriting.closeFile()
        if finished.wait(timeout: .now() + 1) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
        }
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
