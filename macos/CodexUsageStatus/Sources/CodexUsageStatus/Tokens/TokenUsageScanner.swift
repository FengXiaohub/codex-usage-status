import Darwin
import Foundation

/// Reads token counts from local log files written by Codex and Antigravity.
///
/// Privacy: the files also contain conversation text, but only lines carrying token-count
/// markers are decoded, and only numeric token fields, model names and timestamps are kept.
/// Nothing is written to disk or sent anywhere; the incremental cache lives in memory.
final class TokenUsageScanner: @unchecked Sendable {
    static let shared = TokenUsageScanner()

    private enum SourceKind {
        case codexRollout
        case antigravityTranscript
    }

    private struct CodexTotals {
        var input: Int64
        var cached: Int64
        var output: Int64
        var reasoning: Int64
        var total: Int64
    }

    private struct FileState {
        let kind: SourceKind
        let inode: UInt64
        var offset: UInt64 = 0
        var codexModel: String?
        var codexPreviousTotals: CodexTotals?
        var buckets: [TokenBucketKey: TokenCounts] = [:]
    }

    private let lock = NSLock()
    private var fileStates: [String: FileState] = [:]
    private let jsonDecoder = JSONDecoder()
    private let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let plainISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private var calendar = Calendar.current

    private static let tokenCountMarker = Array(#""token_count""#.utf8)
    private static let turnContextMarker = Array(#""turn_context""#.utf8)
    private static let inputTokensMarker = Array(#""input_tokens""#.utf8)
    private static let readChunkSize = 256 * 1024
    private static let maxRetainedCarryCapacity = 64 * 1024

    func scan(now: Date = Date(), windowDays: Int = AppConfig.tokenWindowDays) -> TokenUsageReport {
        lock.lock()
        defer { lock.unlock() }

        calendar = Calendar.current
        let days = max(1, windowDays)
        let startOfToday = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) ?? startOfToday
        let todayKey = dayKey(for: now)
        let windowStartKey = dayKey(for: windowStart)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.readChunkSize, alignment: 16)
        defer { buffer.deallocate() }

        var seen = Set<String>()
        for (path, kind) in candidateFiles(modifiedSince: windowStart) {
            seen.insert(path)
            autoreleasepool {
                process(path: path, kind: kind, scratchBuffer: buffer)
            }
        }
        // Files that were not modified inside the window can only contain older records.
        fileStates = fileStates.filter { seen.contains($0.key) }

        var merged: [TokenBucketKey: TokenCounts] = [:]
        for state in fileStates.values {
            for (key, counts) in state.buckets where key.day >= windowStartKey && key.day <= todayKey {
                merged[key, default: TokenCounts()].add(counts)
            }
        }

        return TokenUsageReport(
            generatedAt: now,
            todayKey: todayKey,
            windowStartKey: windowStartKey,
            windowDays: days,
            buckets: merged,
            scannedFiles: seen.count
        )
    }

    // MARK: - File discovery

    private func candidateFiles(modifiedSince cutoff: Date) -> [(String, SourceKind)] {
        var result: [(String, SourceKind)] = []
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser

        let codexHome: URL
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"], !configured.isEmpty {
            codexHome = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        for directoryName in ["sessions", "archived_sessions"] {
            let root = codexHome.appendingPathComponent(directoryName, isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                // Compressed (.jsonl.zst) rollouts are older finished sessions; they are skipped.
                guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-"),
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= cutoff else {
                    continue
                }
                result.append((url.path, .codexRollout))
            }
        }

        let brainRoot = home.appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
        if let conversations = try? fileManager.contentsOfDirectory(
            at: brainRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for conversation in conversations {
                let transcript = conversation.appendingPathComponent(".system_generated/logs/transcript.jsonl")
                guard let values = try? transcript.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= cutoff else {
                    continue
                }
                result.append((transcript.path, .antigravityTranscript))
            }
        }

        return result
    }

    // MARK: - Incremental reading (zero-copy chunk scan)

    private func process(path: String, kind: SourceKind, scratchBuffer: UnsafeMutableRawPointer) {
        let fd = Darwin.open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else {
            fileStates[path] = nil
            return
        }
        defer { _ = Darwin.close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0 else {
            fileStates[path] = nil
            return
        }
        let size = UInt64(max(0, info.st_size))
        let inode = UInt64(info.st_ino)

        var state = fileStates[path] ?? FileState(kind: kind, inode: inode)
        if state.inode != inode || size < state.offset {
            state = FileState(kind: kind, inode: inode)
        }
        guard size > state.offset else {
            fileStates[path] = state
            return
        }
        guard lseek(fd, off_t(state.offset), SEEK_SET) >= 0 else {
            return
        }

        var remaining = size - state.offset
        var consumed = state.offset
        var carry = Data()

        while remaining > 0 {
            let want = Int(min(remaining, UInt64(Self.readChunkSize)))
            let bytesRead = Darwin.read(fd, scratchBuffer, want)
            if bytesRead < 0 {
                if errno == EINTR { continue }
                break
            }
            if bytesRead == 0 {
                break
            }
            remaining -= UInt64(bytesRead)

            autoreleasepool {
                var position = 0
                if !carry.isEmpty {
                    if let newline = memchr(scratchBuffer, 0x0A, bytesRead) {
                        let prefixLen = scratchBuffer.distance(to: UnsafeMutableRawPointer(newline))
                        if prefixLen > 0 {
                            carry.append(scratchBuffer.assumingMemoryBound(to: UInt8.self), count: prefixLen)
                        }
                        let lineLen = carry.count
                        if lineLen > 0 {
                            carry.withUnsafeBytes { raw in
                                handleLine(raw, state: &state)
                            }
                        }
                        consumed += UInt64(lineLen + 1)
                        if carry.count > Self.maxRetainedCarryCapacity {
                            carry = Data()
                        } else {
                            carry.removeAll(keepingCapacity: true)
                        }
                        position = prefixLen + 1
                    } else {
                        carry.append(scratchBuffer.assumingMemoryBound(to: UInt8.self), count: bytesRead)
                        return
                    }
                }

                while position < bytesRead {
                    guard let newline = memchr(scratchBuffer + position, 0x0A, bytesRead - position) else {
                        let tailLen = bytesRead - position
                        carry.append((scratchBuffer + position).assumingMemoryBound(to: UInt8.self), count: tailLen)
                        break
                    }
                    let newlineIndex = scratchBuffer.distance(to: UnsafeMutableRawPointer(newline))
                    let length = newlineIndex - position
                    if length > 0 {
                        handleLine(UnsafeRawBufferPointer(start: scratchBuffer + position, count: length), state: &state)
                    }
                    consumed += UInt64(length + 1)
                    position = newlineIndex + 1
                }
            }
        }

        // An unterminated trailing line remains in `carry` and is not added to `consumed`,
        // so the next incremental scan re-reads it once the writer finishes appending.
        state.offset = consumed
        fileStates[path] = state
    }

    private func handleLine(_ line: UnsafeRawBufferPointer, state: inout FileState) {
        switch state.kind {
        case .codexRollout:
            if Self.contains(line, Self.tokenCountMarker) {
                handleCodexTokenCount(Data(line), state: &state)
            } else if Self.contains(line, Self.turnContextMarker) {
                handleCodexTurnContext(Data(line), state: &state)
            }
        case .antigravityTranscript:
            if Self.contains(line, Self.inputTokensMarker) {
                handleAntigravityStep(Data(line), state: &state)
            }
        }
    }

    private static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        guard let base = haystack.baseAddress, haystack.count >= needle.count else {
            return false
        }
        return needle.withUnsafeBytes { needleBytes in
            memmem(base, haystack.count, needleBytes.baseAddress, needleBytes.count) != nil
        }
    }

    // MARK: - Codex

    private struct CodexTurnContextLine: Decodable {
        struct Payload: Decodable {
            let model: String?
        }
        let type: String?
        let payload: Payload?
    }

    private struct CodexTokenCountLine: Decodable {
        struct Usage: Decodable {
            let input_tokens: Int64?
            let cached_input_tokens: Int64?
            let output_tokens: Int64?
            let reasoning_output_tokens: Int64?
            let total_tokens: Int64?
        }
        struct Info: Decodable {
            let total_token_usage: Usage?
            let last_token_usage: Usage?
        }
        struct Payload: Decodable {
            let type: String?
            let info: Info?
        }
        let timestamp: String?
        let type: String?
        let payload: Payload?
    }

    private func handleCodexTurnContext(_ data: Data, state: inout FileState) {
        guard let line = try? jsonDecoder.decode(CodexTurnContextLine.self, from: data),
              line.type == "turn_context",
              let model = line.payload?.model, !model.isEmpty else {
            return
        }
        state.codexModel = model
    }

    private func handleCodexTokenCount(_ data: Data, state: inout FileState) {
        guard let line = try? jsonDecoder.decode(CodexTokenCountLine.self, from: data),
              line.type == "event_msg",
              line.payload?.type == "token_count",
              let info = line.payload?.info,
              let timestamp = line.timestamp.flatMap(parseDate) else {
            return
        }

        let totals = info.total_token_usage.map(Self.codexTotals)
        let last = info.last_token_usage.map(Self.codexTotals)

        // Cumulative totals are the most reliable source: repeated events produce a zero delta.
        // The first event of a file (including forked sessions that inherit the parent's totals)
        // and any counter reset fall back to the per-call `last_token_usage`.
        var delta: CodexTotals?
        if let totals, let previous = state.codexPreviousTotals,
           totals.total >= previous.total,
           totals.input >= previous.input,
           totals.cached >= previous.cached,
           totals.output >= previous.output,
           totals.reasoning >= previous.reasoning {
            delta = CodexTotals(
                input: totals.input - previous.input,
                cached: totals.cached - previous.cached,
                output: totals.output - previous.output,
                reasoning: totals.reasoning - previous.reasoning,
                total: totals.total - previous.total
            )
        } else {
            delta = last ?? (state.codexPreviousTotals == nil ? nil : totals)
        }
        if let totals {
            state.codexPreviousTotals = totals
        }

        guard let delta, delta.total > 0 || delta.input > 0 || delta.output > 0 else {
            return
        }

        let cached = min(max(0, delta.cached), max(0, delta.input))
        let counts = TokenCounts(
            input: max(0, delta.input - cached),
            cacheRead: cached,
            output: max(0, delta.output),
            reasoning: max(0, delta.reasoning),
            calls: 1
        )
        let key = TokenBucketKey(day: dayKey(for: timestamp), provider: .codex, model: state.codexModel ?? "unknown")
        state.buckets[key, default: TokenCounts()].add(counts)
    }

    private static func codexTotals(_ usage: CodexTokenCountLine.Usage) -> CodexTotals {
        let input = usage.input_tokens ?? 0
        let output = usage.output_tokens ?? 0
        return CodexTotals(
            input: input,
            cached: usage.cached_input_tokens ?? 0,
            output: output,
            reasoning: usage.reasoning_output_tokens ?? 0,
            total: usage.total_tokens ?? (input + output)
        )
    }

    // MARK: - Antigravity

    private struct AntigravityStepLine: Decodable {
        let created_at: String?
        let model: String?
        let input_tokens: Int64?
        let output_tokens: Int64?
        let cache_read_tokens: Int64?
    }

    private func handleAntigravityStep(_ data: Data, state: inout FileState) {
        guard let line = try? jsonDecoder.decode(AntigravityStepLine.self, from: data),
              let input = line.input_tokens,
              let timestamp = line.created_at.flatMap(parseDate) else {
            return
        }
        let output = line.output_tokens ?? 0
        let cacheRead = line.cache_read_tokens ?? 0
        guard input > 0 || output > 0 || cacheRead > 0 else {
            return
        }

        let model = (line.model?.isEmpty == false ? line.model : nil) ?? "system"
        let counts = TokenCounts(
            input: max(0, input),
            cacheRead: max(0, cacheRead),
            output: max(0, output),
            reasoning: 0,
            calls: 1
        )
        let key = TokenBucketKey(
            day: dayKey(for: timestamp),
            provider: TokenProvider.antigravityProvider(forModel: model),
            model: model
        )
        state.buckets[key, default: TokenCounts()].add(counts)
    }

    // MARK: - Helpers

    private func parseDate(_ raw: String) -> Date? {
        fractionalISO.date(from: raw) ?? plainISO.date(from: raw)
    }

    private func dayKey(for date: Date) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return (components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }
}
