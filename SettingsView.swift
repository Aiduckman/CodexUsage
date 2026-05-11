import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var launchAtLogin = LaunchAtLogin.shared
    private let openAIGreen = Color(red: 0.06, green: 0.64, blue: 0.50)

    var body: some View {
        Form {
            Section("Data Source") {
                LabeledContent("Sessions") {
                    Text("~/.codex/sessions")
                        .font(.body.monospaced())
                }
                LabeledContent("Archive") {
                    Text("~/.codex/archived_sessions")
                        .font(.body.monospaced())
                }
                Text("CodexUsage reads local Codex rollout logs only. It does not store a session token or call OpenAI web endpoints.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Refresh Now") {
                    Task { await viewModel.refresh() }
                }
            }

            Section("Notifications") {
                Toggle("Notify at 80% and 95%", isOn: $viewModel.notificationsEnabled)

                switch notificationManager.authorizationStatus {
                case .notDetermined:
                    Button("Grant notification permission") {
                        Task { await notificationManager.requestAuthorization() }
                    }
                case .denied:
                    Label("Notifications blocked in System Settings", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundColor(.orange)
                case .authorized, .provisional, .ephemeral:
                    Label("Permission granted", systemImage: "checkmark.circle")
                        .font(.caption).foregroundColor(.green)
                @unknown default:
                    EmptyView()
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin.isEnabled)
                Text(launchAtLogin.statusDescription)
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Status") {
                if let usage = viewModel.usage {
                    LabeledContent("Last updated") {
                        Text(usage.lastUpdated, style: .time)
                    }
                    LabeledContent("Log event") {
                        Text(usage.eventTimestamp, style: .time)
                    }
                    if let plan = usage.planType {
                        LabeledContent("Plan") { Text(plan) }
                    }
                    LabeledContent("Session") { Text("\(usage.session.displayPercent)%") }
                    LabeledContent("Week") { Text("\(usage.week.displayPercent)%") }
                    if let source = usage.sourcePath {
                        LabeledContent("Source") {
                            Text(source)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                } else {
                    Text("No data yet.").font(.caption).foregroundColor(.secondary)
                }
                if let error = viewModel.lastError {
                    Text(error).font(.caption).foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .tint(openAIGreen)
        .padding()
        .frame(minWidth: 560, minHeight: 480)
        .onAppear {
            Task { await notificationManager.refreshAuthorizationStatus() }
        }
    }
}
