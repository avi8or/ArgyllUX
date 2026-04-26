import SwiftUI

struct FooterStatusBarView: View {
    let argylluxVersion: String
    let argyllVersion: String
    let toolchainStatusLabel: String
    let toolchainTone: StatusBadgeView.Tone
    let appReadinessLabel: String
    let appReadinessTone: StatusBadgeView.Tone
    let instrumentStatusLabel: String
    let instrumentTone: StatusBadgeView.Tone
    let lastValidationLabel: String
    let isRefreshing: Bool
    let onOpenCliTranscript: () -> Void
    let onOpenDiagnostics: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                StatusBadgeView(title: "Argyll \(toolchainStatusLabel)", tone: toolchainTone)
                StatusBadgeView(title: "App \(appReadinessLabel)", tone: appReadinessTone)
                StatusBadgeView(title: instrumentStatusLabel, tone: instrumentTone)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 14) {
                footerDetail(title: "Last validation", value: lastValidationLabel)
                footerDetail(title: "ArgyllCMS", value: argyllVersion)
                footerDetail(title: "ArgyllUX", value: argylluxVersion)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("CLI Transcript", action: onOpenCliTranscript)
                    .buttonStyle(FooterLinkButtonStyle())

                Button("Diagnostics", action: onOpenDiagnostics)
                    .buttonStyle(FooterLinkButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .font(.caption)
    }

    private func footerDetail(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
