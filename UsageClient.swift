import Foundation

protocol UsageFetching {
    func fetchUsage() async throws -> UsageData
}

enum UsageError: LocalizedError {
    case noCodexDirectory
    case noUsageFiles
    case noRateLimitEvents
    case unreadableLog(String)

    var errorDescription: String? {
        switch self {
        case .noCodexDirectory:
            return "No ~/.codex directory found."
        case .noUsageFiles:
            return "No Codex rollout logs found in ~/.codex/sessions or ~/.codex/archived_sessions."
        case .noRateLimitEvents:
            return "No Codex rate-limit events found yet. Use Codex once, then refresh."
        case .unreadableLog(let path):
            return "Couldn't read Codex log: \(path)"
        }
    }
}

final class CodexUsageClient: UsageFetching {
    private let homeDirectory: URL
    private let fileManager: FileManager
    private static let tailChunkByteCount = 64 * 1024
    private static let maxLineByteCount = 1024 * 1024
    private static let tokenCountNeedle = Data(#""token_count""#.utf8)
    private static let rateLimitsNeedle = Data(#""rate_limits""#.utf8)

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func fetchUsage() async throws -> UsageData {
        let homeDirectory = self.homeDirectory
        let fileManager = self.fileManager

        return try await Task.detached(priority: .utility) {
            try Self.readLatestUsage(homeDirectory: homeDirectory, fileManager: fileManager)
        }.value
    }

    private static func readLatestUsage(homeDirectory: URL, fileManager: FileManager) throws -> UsageData {
        let codexRoot = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        guard fileManager.fileExists(atPath: codexRoot.path) else {
            throw UsageError.noCodexDirectory
        }

        let files = rolloutFiles(in: codexRoot, fileManager: fileManager)
        guard !files.isEmpty else { throw UsageError.noUsageFiles }

        var latest: RateLimitSample?
        for file in files {
            if let latest, file.modifiedAt <= latest.timestamp {
                break
            }

            guard let sample = try latestSample(in: file.url) else { continue }
            if latest == nil || sample.timestamp > latest!.timestamp {
                latest = sample
            }
        }

        guard let latest else { throw UsageError.noRateLimitEvents }
        return latest.toUsageData(lastUpdated: Date())
    }

    private struct RolloutFile {
        let url: URL
        let modifiedAt: Date
    }

    private static func rolloutFiles(in codexRoot: URL, fileManager: FileManager) -> [RolloutFile] {
        let roots = [
            codexRoot.appendingPathComponent("sessions", isDirectory: true),
            codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
        ]

        return roots.flatMap { root -> [RolloutFile] in
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            ) else {
                return []
            }

            var urls: [RolloutFile] = []
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      url.lastPathComponent.hasPrefix("rollout-"),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true
                else {
                    continue
                }
                urls.append(RolloutFile(
                    url: url,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                ))
            }
            return urls
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private static func latestSample(in file: URL) throws -> RateLimitSample? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file)
        } catch {
            throw UsageError.unreadableLog(file.path)
        }
        defer { try? handle.close() }

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
        } catch {
            throw UsageError.unreadableLog(file.path)
        }

        guard fileSize > 0 else { return nil }

        let decoder = JSONDecoder.codexDecoder
        var offset = fileSize
        var suffix = Data()
        suffix.reserveCapacity(maxLineByteCount)
        var skippingOversizedLine = false

        while offset > 0 {
            let readSize = Int(min(UInt64(tailChunkByteCount), offset))
            offset -= UInt64(readSize)

            let chunk: Data
            do {
                try handle.seek(toOffset: offset)
                chunk = try handle.read(upToCount: readSize) ?? Data()
            } catch {
                throw UsageError.unreadableLog(file.path)
            }
            guard !chunk.isEmpty else { continue }

            var buffer = Data()
            buffer.reserveCapacity(chunk.count + suffix.count)
            buffer.append(chunk)
            buffer.append(suffix)
            suffix.removeAll(keepingCapacity: true)

            var upperBound = buffer.count
            while upperBound > 0 {
                guard let newlineIndex = buffer[..<upperBound].lastIndex(of: 0x0A) else {
                    if !skippingOversizedLine {
                        if upperBound <= maxLineByteCount {
                            suffix = Data(buffer[..<upperBound])
                        } else {
                            skippingOversizedLine = true
                        }
                    }
                    break
                }

                let lineStart = buffer.index(after: newlineIndex)
                if lineStart < upperBound, !skippingOversizedLine {
                    let line = buffer[lineStart..<upperBound]
                    if let sample = decodeSampleLine(line, decoder: decoder, sourcePath: file.path) {
                        return sample
                    }
                }

                skippingOversizedLine = false
                upperBound = newlineIndex
            }
        }

        if !suffix.isEmpty, !skippingOversizedLine {
            return decodeSampleLine(suffix, decoder: decoder, sourcePath: file.path)
        }

        return nil
    }

    private static func decodeSampleLine(
        _ line: Data.SubSequence,
        decoder: JSONDecoder,
        sourcePath: String
    ) -> RateLimitSample? {
        guard line.count <= maxLineByteCount else { return nil }

        let data = Data(line)
        guard data.range(of: tokenCountNeedle) != nil,
              data.range(of: rateLimitsNeedle) != nil
        else {
            return nil
        }

        do {
            let event = try decoder.decode(CodexLogEvent.self, from: data)
            guard event.payload.type == "token_count",
                  let rateLimits = event.payload.rateLimits
            else {
                return nil
            }
            return RateLimitSample(
                timestamp: event.timestamp,
                rateLimits: rateLimits,
                sourcePath: sourcePath
            )
        } catch {
            return nil
        }
    }
}

private struct RateLimitSample {
    let timestamp: Date
    let rateLimits: RawRateLimits
    let sourcePath: String

    func toUsageData(lastUpdated: Date) -> UsageData {
        func toWindow(_ raw: RawRateLimitWindow) -> UsageWindow {
            let windowMinutes = raw.windowMinutes
            let windowSeconds = TimeInterval(windowMinutes ?? 0) * 60
            var utilization = Self.normalizedPercent(raw.usedPercent)
            var resetsAt = raw.resetsAt.map(Date.init(timeIntervalSince1970:))
                ?? lastUpdated.addingTimeInterval(TimeInterval(windowMinutes ?? 60) * 60)

            if windowSeconds > 0, resetsAt <= lastUpdated {
                utilization = 0
                repeat {
                    resetsAt.addTimeInterval(windowSeconds)
                } while resetsAt <= lastUpdated
            }

            return UsageWindow(
                utilization: utilization,
                resetsAt: resetsAt,
                windowMinutes: windowMinutes
            )
        }

        return UsageData(
            session: toWindow(rateLimits.primary),
            week: toWindow(rateLimits.secondary),
            planType: rateLimits.planType,
            limitID: rateLimits.limitID,
            rateLimitReachedType: rateLimits.rateLimitReachedType,
            eventTimestamp: timestamp,
            lastUpdated: lastUpdated,
            sourcePath: sourcePath
        )
    }

    private static func normalizedPercent(_ value: Double) -> Double {
        min(max(value / 100.0, 0), 1)
    }
}

private struct CodexLogEvent: Decodable {
    let timestamp: Date
    let payload: Payload

    struct Payload: Decodable {
        let type: String
        let rateLimits: RawRateLimits?

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }
    }
}

private struct RawRateLimits: Decodable {
    let limitID: String?
    let limitName: String?
    let primary: RawRateLimitWindow
    let secondary: RawRateLimitWindow
    let planType: String?
    let rateLimitReachedType: String?

    enum CodingKeys: String, CodingKey {
        case limitID = "limit_id"
        case limitName = "limit_name"
        case primary
        case secondary
        case planType = "plan_type"
        case rateLimitReachedType = "rate_limit_reached_type"
    }
}

private struct RawRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }
}

private extension JSONDecoder {
    static let codexDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)

            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFrac.date(from: str) { return date }

            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: str) { return date }

            if let dot = str.firstIndex(of: ".") {
                let after = str.index(after: dot)
                var end = after
                while end < str.endIndex, str[end].isNumber {
                    end = str.index(after: end)
                }
                let digits = str[after..<end]
                if digits.count > 3 {
                    let trimmed = str.replacingCharacters(in: after..<end, with: String(digits.prefix(3)))
                    if let date = withFrac.date(from: trimmed) { return date }
                }
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(str)"
            )
        }
        return d
    }()
}

// Mock client used during development. To enable: CodexUsageApp.swift -> useMock: true.
final class MockUsageClient: UsageFetching {
    private var tick = 0

    func fetchUsage() async throws -> UsageData {
        try await Task.sleep(nanoseconds: 300_000_000)
        tick += 1
        let session = min(0.05 + Double(tick) * 0.07, 0.98)
        return UsageData(
            session: UsageWindow(
                utilization: session,
                resetsAt: Date().addingTimeInterval(2 * 3600 + 17 * 60),
                windowMinutes: 300
            ),
            week: UsageWindow(
                utilization: 0.41,
                resetsAt: Date().addingTimeInterval(4 * 24 * 3600),
                windowMinutes: 10_080
            ),
            planType: "plus",
            limitID: "codex",
            rateLimitReachedType: nil,
            eventTimestamp: Date(),
            lastUpdated: Date(),
            sourcePath: "~/.codex/sessions/example/rollout-example.jsonl"
        )
    }
}
