import Foundation

enum AppConfig {
    static let defaultCodexPaths = [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/Applications/Codex.app/Contents/Resources/codex",
    ]
    static var defaultAgyPaths: [String] {
        [
            NSHomeDirectory() + "/.local/bin/agy",
            "/Applications/Antigravity.app/Contents/Resources/bin/agy",
            "/usr/local/bin/agy",
            "/opt/homebrew/bin/agy",
        ]
    }
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
    static let errorRetryInterval: TimeInterval = 300
    static let appServerTimeout: DispatchTimeInterval = .seconds(20)
}

func configuredRefreshInterval() -> TimeInterval {
    let rawValue = ProcessInfo.processInfo.environment["CODEX_USAGE_REFRESH_SECONDS"]
    let requested = rawValue.flatMap(Double.init) ?? AppConfig.defaultRefreshInterval
    return max(AppConfig.minimumRefreshInterval, requested)
}
