import AppKit
import Darwin
import Foundation

@main
enum CodexUsageStatusEntry {
    static func main() {
        signal(SIGPIPE, SIG_IGN)

        if CommandLine.arguments.contains("--tokens") {
            print(TokenUsageScanner.shared.scan().textSummary)
            exit(0)
        }

        if CommandLine.arguments.contains("--once") {
            do {
                let usage = try CodexUsageFetcher.fetchCombinedSync()
                print(usage.menuTitle)
                exit(0)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}
