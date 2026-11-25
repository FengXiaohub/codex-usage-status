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
        let envelope = try readAntigravityUsage()
        return try UsageSummary.parseAntigravityGroups(from: envelope)
    }

    private static func readAntigravityUsage() throws -> AntigravityUsageEnvelope {
        let configuredPath = ProcessInfo.processInfo.environment["AGY_BIN"]
        let agyPath = configuredPath ?? AppConfig.defaultAgyPaths.first(where: FileManager.default.isExecutableFile(atPath:)) ?? AppConfig.defaultAgyPaths[0]
        guard FileManager.default.isExecutableFile(atPath: agyPath) else {
            throw FetchError.antigravityNotFound(agyPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: agyPath)
        process.arguments = ["-p", "/usage", "--output-format", "json"]

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        let outputBox = DataAccumulatorBox()
        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            outputBox.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        if finished.wait(timeout: .now() + AppConfig.appServerTimeout) == .timedOut {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            terminateProcess(process, finished: finished)
            throw FetchError.timeout
        }

        standardOutput.fileHandleForReading.readabilityHandler = nil
        let remaining = standardOutput.fileHandleForReading.readDataToEndOfFile()
        outputBox.append(remaining)
        _ = standardError.fileHandleForReading.readDataToEndOfFile()

        guard let text = String(data: outputBox.data(), encoding: .utf8) else {
            throw FetchError.invalidOutput
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let jsonLine = lines.reversed().first(where: { $0.hasPrefix("{") && $0.hasSuffix("}") }),
              let jsonData = jsonLine.data(using: .utf8) else {
            throw FetchError.missingRateLimitResponse
        }

        return try JSONDecoder().decode(AntigravityUsageEnvelope.self, from: jsonData)
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
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_usage_status_menubar","title":"Codex Usage Status","version":"0.4.0"},"capabilities":{"experimentalApi":true}}}"#,
            #"{"method":"initialized"}"#,
            #"{"method":"account/rateLimits/read","id":2}"#
        ].joined(separator: "\n") + "\n"

        standardInput.fileHandleForWriting.write(Data(requestLines.utf8))

        if responseBox.wait(timeout: .now() + AppConfig.appServerTimeout) == .timedOut {
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

enum FetchError: LocalizedError {
    case codexNotFound(String)
    case antigravityNotFound(String)
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
