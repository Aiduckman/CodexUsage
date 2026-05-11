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
            guard let sample = try latestSample(in: file) else { continue }
            if latest == nil || sample.timestamp > latest!.timestamp {
                latest = sample
            }
        }

        guard let latest else { throw UsageError.noRateLimitEvents }
        return latest.toUsageData(lastUpdated: Date())
    }

    private static func rolloutFiles(in codexRoot: URL, fileManager: FileManager) -> [URL] {
        let roots = [
            codexRoot.appendingPathComponent("sessions", isDirectory: true),
            codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
        ]

        return roots.flatMap { root -> [URL] in
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants]
            ) else {
                return []
            }

            var urls: [URL] = []
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      url.lastPathComponent.hasPrefix("rollout-")
                else {
                    continue
                }
                urls.append(url)
            }
            return urls
        }
    }

    private static func latestSample(in file: URL) throws -> RateLimitSample? {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw UsageError.unreadableLog(file.path)
        }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let decoder = JSONDecoder.codexDecoder

        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("\"token_count\""),
                  line.contains("\"rate_limits\"")
            else {
                continue
            }

            do {
                let event = try decoder.decode(CodexLogEvent.self, from: Data(line.utf8))
                guard event.payload.type == "token_count",
                      let rateLimits = event.payload.rateLimits
                else {
                    continue
                }
                return RateLimitSample(
                    timestamp: event.timestamp,
                    rateLimits: rateLimits,
                    sourcePath: file.path
                )
            } catch {
                continue
            }
        }

        return nil
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
