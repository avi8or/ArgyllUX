import SwiftUI

enum LogViewerKind: String, Identifiable {
    case error

    var id: String { rawValue }

    var title: String {
        "Error Log Viewer"
    }
}

struct LogViewerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let kind: LogViewerKind

    private var filteredEntries: [LogEntry] {
        model.recentLogs.filter { $0.level.lowercased() == "error" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.title)
                        .font(.title2.weight(.semibold))
                    Text(model.storagePaths.logPath)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Button("Refresh") {
                    Task { await model.refreshLogs(limit: 200) }
                }
            }
            .padding(20)

            Divider()

            if filteredEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No log entries available for this view.")
                        .font(.subheadline)
                    Text("Errors from the engine log will appear here when they exist.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            } else {
                List(filteredEntries, id: \.timestamp) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(entry.level.uppercased()) • \(entry.source)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.subheadline)
                        Text(entry.timestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)
        }
        .frame(minWidth: 760, minHeight: 420)
        .task {
            await model.refreshLogs(limit: 200)
        }
    }
}
