import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            apply(isEnabled)
        }
    }

    private init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func apply(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Task { @MainActor in
                self.isEnabled = (SMAppService.mainApp.status == .enabled)
            }
        }
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered:     return "Not registered"
        case .enabled:           return "Enabled"
        case .requiresApproval:  return "Approval required in System Settings → Login Items"
        case .notFound:          return "Not found — move app to /Applications first"
        @unknown default:        return "Unknown"
        }
    }
}
