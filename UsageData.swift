import Foundation

struct UsageData: Equatable {
    let session: UsageWindow
    let week: UsageWindow
    let planType: String?
    let limitID: String?
    let rateLimitReachedType: String?
    let eventTimestamp: Date
    let lastUpdated: Date
    let sourcePath: String?
}

struct UsageWindow: Equatable {
    let utilization: Double
    let resetsAt: Date
    let windowMinutes: Int?

    var displayPercent: Int { Int((utilization * 100).rounded()) }
    var safeValue: Double { min(max(utilization, 0), 1) }

    var durationLabel: String {
        guard let minutes = windowMinutes else { return "" }
        if minutes % (24 * 60) == 0 {
            return "\(minutes / (24 * 60))d"
        }
        if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }
}
