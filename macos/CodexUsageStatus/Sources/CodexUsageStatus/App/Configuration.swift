import Foundation

enum AppConfig {
    static let defaultCodexPaths = [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/Applications/Codex.app/Contents/Resources/codex",
    ]
    static var watchedClientPaths: [String] {
        [
            "/Applications/Antigravity.app/Contents/Info.plist",
            "/Applications/ChatGPT.app/Contents/Info.plist",
            "/Applications/Codex.app/Contents/Info.plist",
            NSHomeDirectory() + "/.local/bin/agy",
        ]
    }
    static let minimumRefreshInterval: TimeInterval = 60
    static let defaultRefreshInterval: TimeInterval = 120
    static let transientRetryInterval: TimeInterval = 30
    static let errorRetryInterval: TimeInterval = 120
    static let wakeRefreshDelay: TimeInterval = 5
    static let maxStaleFailuresBeforeError = 2
    static let appServerTimeoutSeconds = 20
    static let antigravityRequestTimeoutSeconds = 10
    /// A refresh that has not finished after this long is treated as stuck and superseded.
    static let refreshWatchdogInterval: TimeInterval = 90
    /// Token statistics cover today plus the previous days up to this many calendar days.
    static let tokenWindowDays = 7
    /// Opening the menu rescans token logs at most this often.
    static let tokenRescanThrottle: TimeInterval = 15
    /// Remaining quota strictly below this percentage is highlighted in red in the menu bar.
    static let lowQuotaRedThresholdPercent = 15

    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }
}

func configuredRefreshInterval() -> TimeInterval {
    let rawValue = ProcessInfo.processInfo.environment["CODEX_USAGE_REFRESH_SECONDS"]
    let requested = rawValue.flatMap(Double.init) ?? AppConfig.defaultRefreshInterval
    return max(AppConfig.minimumRefreshInterval, requested)
}
