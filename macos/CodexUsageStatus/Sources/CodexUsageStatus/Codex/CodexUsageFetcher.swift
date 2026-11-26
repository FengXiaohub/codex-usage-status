import CFNetwork
import Darwin
import Foundation

enum CodexUsageFetcher {
    static func fetchCombined() async throws -> CombinedUsageSummary {
        async let codexTask: Result<UsageSummary, Error> = Task.detached(priority: .utility) {
            Result { try fetchSync() }
        }.value
        async let agyTask: Result<(gemini: UsageSummary?, claudeGpt: UsageSummary?), Error> = Task.detached(priority: .utility) {
            Result { try fetchAntigravitySync() }
        }.value

        let codexResult = await codexTask
        let agyResult = await agyTask

        var codexUsage: UsageSummary?
        var codexError: String?
        switch codexResult {
        case .success(let summary):
            codexUsage = summary
        case .failure(let error):
            codexError = error.localizedDescription
        }

        var geminiUsage: UsageSummary?
        var claudeGptUsage: UsageSummary?
        var agyError: String?
        switch agyResult {
        case .success(let groups):
            geminiUsage = groups.gemini
            claudeGptUsage = groups.claudeGpt
        case .failure(let error):
            if case FetchError.antigravityNotRunning = error {
                agyError = nil
            } else {
                agyError = error.localizedDescription
            }
        }

        let combined = CombinedUsageSummary(
            codex: codexUsage,
            gemini: geminiUsage,
            claudeGpt: claudeGptUsage,
            codexError: codexError,
            antigravityError: agyError
        )

        guard combined.hasAnyUsage else {
            throw FetchError.allProvidersUnavailable(
                codex: codexError ?? "unavailable",
                antigravity: agyError ?? "unavailable"
            )
        }
        return combined
    }

    static func fetchCombinedSync() throws -> CombinedUsageSummary {
        var codexUsage: UsageSummary?
        var codexError: String?
        do {
            codexUsage = try fetchSync()
        } catch {
            codexError = error.localizedDescription
        }

        var geminiUsage: UsageSummary?
        var claudeGptUsage: UsageSummary?
        var agyError: String?
        do {
            let groups = try fetchAntigravitySync()
            geminiUsage = groups.gemini
            claudeGptUsage = groups.claudeGpt
        } catch FetchError.antigravityNotRunning {
            agyError = nil
        } catch {
            agyError = error.localizedDescription
        }

        let combined = CombinedUsageSummary(
            codex: codexUsage,
            gemini: geminiUsage,
            claudeGpt: claudeGptUsage,
            codexError: codexError,
            antigravityError: agyError
        )

        guard combined.hasAnyUsage else {
            throw FetchError.allProvidersUnavailable(
                codex: codexError ?? "unavailable",
                antigravity: agyError ?? "unavailable"
            )
        }
        return combined
    }

    static func fetch() async throws -> UsageSummary {
        try await Task.detached(priority: .utility) {
            try fetchSync()
        }.value
    }

    static func fetchSync() throws -> UsageSummary {
        let response = try readRateLimits()
        return try UsageSummary(response: response)
    }

    static func fetchAntigravitySync() throws -> (gemini: UsageSummary?, claudeGpt: UsageSummary?) {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let envelope = try readAntigravityUsageFromLocalDaemon()
                return try UsageSummary.parseAntigravityGroups(from: envelope)
            } catch FetchError.antigravityNotRunning {
                throw FetchError.antigravityNotRunning
            } catch {
                lastError = error
                if attempt == 0 {
                    Thread.sleep(forTimeInterval: 1.0)
                }
            }
        }
        throw lastError ?? FetchError.missingRateLimitResponse
    }

    private struct AntigravityDaemonDiscovery: Decodable {
        let pid: Int32?
        let httpPort: Int?
        let csrfToken: String?
    }

    private static func discoverLiveAntigravityDaemons() -> [(port: Int, csrfToken: String)] {
        let daemonDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/daemon", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: daemonDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let hubFiles = entries
            .filter { $0.lastPathComponent.hasPrefix("hub_") && $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lDate > rDate
            }

        var live: [(port: Int, csrfToken: String)] = []
        let decoder = JSONDecoder()
        for fileURL in hubFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let discovery = try? decoder.decode(AntigravityDaemonDiscovery.self, from: data),
                  let pid = discovery.pid, pid > 0, kill(pid, 0) == 0,
                  let port = discovery.httpPort, (1...65535).contains(port),
                  let csrfToken = discovery.csrfToken, !csrfToken.isEmpty else {
                continue
            }
            live.append((port: port, csrfToken: csrfToken))
        }
        return live
    }

    private static func readAntigravityUsageFromLocalDaemon() throws -> AntigravityUsageEnvelope {
        let daemons = discoverLiveAntigravityDaemons()
        guard !daemons.isEmpty else {
            throw FetchError.antigravityNotRunning
        }

        var lastError: Error = FetchError.missingRateLimitResponse
        for daemon in daemons {
            guard let url = URL(string: "http://127.0.0.1:\(daemon.port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.setValue(daemon.csrfToken, forHTTPHeaderField: "x-antigravity-csrf-token")

            let config = URLSessionConfiguration.ephemeral
            // Force direct loopback to 127.0.0.1 so corporate VPN / PAC / system proxies never intercept local IPC.
            config.connectionProxyDictionary = [:]
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 10

            let session = URLSession(configuration: config)
            defer { session.finishTasksAndInvalidate() }

            let semaphore = DispatchSemaphore(value: 0)
            let resultBox = HTTPResultBox()

            let task = session.dataTask(with: request) { data, response, error in
                resultBox.store(data: data, response: response, error: error)
                semaphore.signal()
            }
            task.resume()

            if semaphore.wait(timeout: .now() + .seconds(10)) == .timedOut {
                task.cancel()
                lastError = FetchError.timeout
                continue
            }

            let outcome = resultBox.load()
            if let error = outcome.error {
                lastError = error
                continue
            }
            guard let httpResponse = outcome.response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data = outcome.data, !data.isEmpty else {
                lastError = FetchError.invalidOutput
                continue
            }

            return try JSONDecoder().decode(AntigravityUsageEnvelope.self, from: data)
        }

        throw lastError
    }

    private static func readRateLimits() throws -> RateLimitsResponse {
        let configuredPath = ProcessInfo.processInfo.environment["CODEX_BIN"]
        let codexPath = configuredPath ?? AppConfig.defaultCodexPaths.first(where: FileManager.default.isExecutableFile(atPath:)) ?? AppConfig.defaultCodexPaths[0]
        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            throw FetchError.codexNotFound(codexPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = isolatedWorkingDirectoryURL()
        process.environment = environmentWithSystemProxy()

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
        let errorBox = DataAccumulatorBox()
        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            responseBox.append(handle.availableData)
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
            errorBox.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        let requestLines = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_usage_status_menubar","title":"Codex Usage Status","version":"0.4.2"},"capabilities":{"experimentalApi":true}}}"#,
            #"{"method":"initialized"}"#,
            #"{"method":"account/rateLimits/read","id":2}"#
        ].joined(separator: "\n") + "\n"

        do {
            try standardInput.fileHandleForWriting.write(contentsOf: Data(requestLines.utf8))
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            try? standardInput.fileHandleForWriting.close()
            terminateProcess(process, finished: finished)
            throw FetchError.appServerError
        }

        if responseBox.wait(timeout: .now() + AppConfig.appServerTimeout) == .timedOut {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            try? standardInput.fileHandleForWriting.close()
            terminateProcess(process, finished: finished)
            throw FetchError.timeout
        }

        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
        try? standardInput.fileHandleForWriting.close()
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

    private static func environmentWithSystemProxy() -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        let extraPaths = [
            NSHomeDirectory() + "/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let existingPath = env["PATH"] ?? ""
        let existingParts = existingPath.split(separator: ":").map(String.init)
        let mergedParts = extraPaths.filter { !existingParts.contains($0) } + existingParts
        env["PATH"] = mergedParts.joined(separator: ":")

        guard let proxyDict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return env
        }

        let httpEnabled = (proxyDict[kCFNetworkProxiesHTTPEnable as String] as? NSNumber)?.boolValue ?? false
        var httpProxyURL: String?
        if httpEnabled,
           let host = proxyDict[kCFNetworkProxiesHTTPProxy as String] as? String,
           let port = proxyDict[kCFNetworkProxiesHTTPPort as String] as? NSNumber {
            let url = "http://\(host):\(port.intValue)"
            httpProxyURL = url
            if env["http_proxy"] == nil && env["HTTP_PROXY"] == nil {
                env["http_proxy"] = url
                env["HTTP_PROXY"] = url
            }
        }

        let httpsEnabled = (proxyDict[kCFNetworkProxiesHTTPSEnable as String] as? NSNumber)?.boolValue ?? false
        var httpsProxyURL: String?
        if httpsEnabled,
           let host = proxyDict[kCFNetworkProxiesHTTPSProxy as String] as? String,
           let port = proxyDict[kCFNetworkProxiesHTTPSPort as String] as? NSNumber {
            let url = "http://\(host):\(port.intValue)"
            httpsProxyURL = url
            if env["https_proxy"] == nil && env["HTTPS_PROXY"] == nil {
                env["https_proxy"] = url
                env["HTTPS_PROXY"] = url
            }
        }

        if let preferredAllProxy = httpsProxyURL ?? httpProxyURL {
            if env["all_proxy"] == nil && env["ALL_PROXY"] == nil {
                env["all_proxy"] = preferredAllProxy
                env["ALL_PROXY"] = preferredAllProxy
            }
        } else {
            let socksEnabled = (proxyDict[kCFNetworkProxiesSOCKSEnable as String] as? NSNumber)?.boolValue ?? false
            if socksEnabled,
               let host = proxyDict[kCFNetworkProxiesSOCKSProxy as String] as? String,
               let port = proxyDict[kCFNetworkProxiesSOCKSPort as String] as? NSNumber {
                let url = "socks5://\(host):\(port.intValue)"
                if env["all_proxy"] == nil && env["ALL_PROXY"] == nil {
                    env["all_proxy"] = url
                    env["ALL_PROXY"] = url
                }
            }
        }

        if env["no_proxy"] == nil && env["NO_PROXY"] == nil {
            let defaultNoProxy = "localhost,127.0.0.1,::1,*.local"
            env["no_proxy"] = defaultNoProxy
            env["NO_PROXY"] = defaultNoProxy
        }

        return env
    }

    private static func isolatedWorkingDirectoryURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-usage-status-empty-cwd", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
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

final class DataAccumulatorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

final class HTTPResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var response: URLResponse?
    private var error: Error?

    func store(data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        self.data = data
        self.response = response
        self.error = error
        lock.unlock()
    }

    func load() -> (data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (data, response, error)
    }
}

enum FetchError: LocalizedError {
    case codexNotFound(String)
    case antigravityNotFound(String)
    case antigravityNotRunning
    case allProvidersUnavailable(codex: String, antigravity: String)
    case timeout
    case appServerExited(Int)
    case appServerError
    case invalidOutput
    case missingRateLimitResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound(let path):
            return "Codex binary not found at \(path)"
        case .antigravityNotFound(let path):
            return "Antigravity CLI (agy) binary not found at \(path)"
        case .antigravityNotRunning:
            return "Antigravity desktop app is not running"
        case .allProvidersUnavailable(let codex, let antigravity):
            return "Codex (\(codex)); Antigravity (\(antigravity))"
        case .timeout:
            return "Local usage query did not respond within 20 seconds"
        case .appServerExited(let status):
            return "Codex app-server exited with status \(status)"
        case .appServerError:
            return "Codex app-server returned an error"
        case .invalidOutput:
            return "Local usage query returned unexpected data"
        case .missingRateLimitResponse:
            return "Local usage query did not return usage data"
        }
    }
}
