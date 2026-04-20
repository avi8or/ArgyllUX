import SwiftUI

struct FooterStatusBarView: View {
    let argylluxVersion: String
    let argyllVersion: String
    let instrumentStatusLabel: String
    let onOpenCliTranscript: () -> Void
    let onOpenErrorLogs: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            footerGroup(title: "ArgyllUX", value: argylluxVersion)
            footerGroup(title: "ArgyllCMS", value: argyllVersion)
            footerGroup(title: "Instrument", value: instrumentStatusLabel)

            Spacer()

            Button("CLI Transcript", action: onOpenCliTranscript)
                .buttonStyle(.link)

            Button("Error Log Viewer", action: onOpenErrorLogs)
                .buttonStyle(.link)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .font(.caption)
    }

    private func footerGroup(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}
