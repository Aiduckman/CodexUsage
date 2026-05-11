import Foundation
import Combine
import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var usage: UsageData?
    @Published private(set) var lastError: String?
    @Published private(set) var isLoading = false

    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    private let client: UsageFetching
    private var pollingTask: Task<Void, Never>?

    private let pollingInterval: TimeInterval = 60
    private let thresholds: [Int] = [80, 95]
    private let hysteresisMargin = 0.05
    private var firedThresholds: Set<String> = []

    private enum Keys {
        static let notificationsEnabled = "codexusage.notificationsEnabled"
    }

    init(useMock: Bool = false) {
        self.client = useMock ? MockUsageClient() : CodexUsageClient()
        self.notificationsEnabled = UserDefaults.standard.object(forKey: Keys.notificationsEnabled) as? Bool ?? true

        Task { [weak self] in await self?.start() }
    }

    func start() async {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await client.fetchUsage()
            self.usage = data
            self.lastError = nil
            checkThresholds(data)
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    private func checkThresholds(_ data: UsageData) {
        guard notificationsEnabled else { return }

        let windows: [(String, Double)] = [
            ("Session", data.session.utilization),
            ("Week",    data.week.utilization)
        ]

        for (name, utilization) in windows {
            for threshold in thresholds {
                let key = "\(name)-\(threshold)"
                let target = Double(threshold) / 100.0

                if utilization >= target, !firedThresholds.contains(key) {
                    firedThresholds.insert(key)
                    NotificationManager.shared.sendThresholdAlert(windowName: name, percentage: threshold)
                } else if utilization < target - hysteresisMargin {
                    firedThresholds.remove(key)  // re-arm when usage drops back down
                }
            }
        }
    }

    // MARK: - Menu bar derived state

    var menuBarLabel: String {
        guard let usage = usage else { return "—" }
        return "\(usage.session.displayPercent)%"
    }

    var menuBarNumberColor: Color {
        guard let usage = usage else { return .gray }
        if usage.session.utilization >= 0.9 {
            return .red
        }
        return .orange
    }

    var menuBarLevel: AlertLevel {
        guard let usage = usage else { return .neutral }
        let worst = max(
            usage.session.utilization,
            usage.week.utilization
        )
        if worst >= 0.9 { return .danger }
        if worst >= 0.7 { return .warning }
        return .ok
    }
}

enum AlertLevel {
    case ok, warning, danger, neutral

    init(for utilization: Double) {
        if utilization >= 0.9 {
            self = .danger
        } else if utilization >= 0.7 {
            self = .warning
        } else {
            self = .ok
        }
    }

    var color: Color {
        switch self {
        case .ok: return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .warning: return .orange
        case .danger: return .red
        case .neutral: return .gray
        }
    }

}
