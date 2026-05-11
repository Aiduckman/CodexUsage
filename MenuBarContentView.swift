import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: UsageViewModel

    private let openAIGreen = Color(red: 0.06, green: 0.64, blue: 0.50)
    private let openAIDark = Color(red: 0.05, green: 0.06, blue: 0.055)
    private let openAIMuted = Color(red: 0.70, green: 0.74, blue: 0.70)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
                .overlay(openAIGreen.opacity(0.28))
            content
            Divider()
                .overlay(openAIGreen.opacity(0.20))
            footer
        }
        .padding(12)
        .frame(width: 286)
        .background(
            LinearGradient(
                colors: [
                    openAIDark.opacity(0.96),
                    Color(red: 0.08, green: 0.11, blue: 0.09).opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundColor(openAIGreen)
            Text("CodexUsage").font(.headline)
                .foregroundColor(.white)
            Spacer()
            if viewModel.isLoading {
                ProgressView().controlSize(.small).tint(openAIGreen)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let usage = viewModel.usage {
            windowRow(title: "Session", window: usage.session)
            windowRow(title: "Week", window: usage.week)
            HStack {
                Spacer()
                Text("Updated \(usage.lastUpdated, style: .time)")
                    .font(.caption2).foregroundColor(openAIMuted)
            }
        } else if let error = viewModel.lastError {
            VStack(alignment: .leading, spacing: 6) {
                Label("Error", systemImage: "exclamationmark.triangle")
                    .font(.caption.bold()).foregroundColor(.red)
                Text(error).font(.caption).foregroundColor(openAIMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack {
                ProgressView().controlSize(.small).tint(openAIGreen)
                Text("Loading…").font(.caption).foregroundColor(openAIMuted)
            }
        }
    }

    private func windowRow(title: String, window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.durationLabel.isEmpty ? title : "\(title) (\(window.durationLabel))")
                    .font(.caption)
                    .foregroundColor(openAIMuted)
                Spacer()
                Text("\(window.displayPercent)%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(tint(for: window.utilization))
            }
            ProgressView(value: window.safeValue)
                .tint(tint(for: window.utilization))
            Text("Resets \(window.resetsAt, style: .relative)")
                .font(.caption2).foregroundColor(openAIMuted.opacity(0.92))
        }
    }

    private func tint(for pct: Double) -> Color {
        if pct >= 0.9 { return .red }
        if pct >= 0.7 { return .orange }
        return openAIGreen
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(openAIGreen)
            }
            .help("Refresh")

            Spacer()

            SettingsLink { Text("Settings…") }
                .foregroundColor(openAIMuted)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .foregroundColor(openAIMuted)
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}
