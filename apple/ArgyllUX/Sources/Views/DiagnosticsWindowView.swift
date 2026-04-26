import SwiftUI

/// Separate technical surface for privacy-safe diagnostics summaries and events.
struct DiagnosticsWindowView: View {
    static let windowID = "diagnostics"

    @Environment(\.openWindow) private var openWindow
    @ObservedObject var diagnostics: DiagnosticsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filters
            Divider()

            HStack(spacing: 0) {
                eventList
                    .frame(minWidth: 420, idealWidth: 520, maxWidth: 640)

                Divider()

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .task {
            await diagnostics.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Diagnostics")
                    .font(.title2.weight(.semibold))
                Text("Privacy-safe app, workflow, toolchain, and command summary events.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if diagnostics.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Refreshing diagnostics")
            }

            Button("Refresh") {
                Task { await diagnostics.refresh() }
            }
            .disabled(diagnostics.isLoading)
        }
        .padding(20)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("Level", selection: $diagnostics.levelFilter) {
                ForEach(DiagnosticsLevelFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)

            Picker("Category", selection: $diagnostics.categoryFilter) {
                ForEach(DiagnosticsCategoryFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)

            TextField("Search diagnostics", text: $diagnostics.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)

            Toggle("Errors Only", isOn: $diagnostics.errorsOnly)

            Button("Apply") {
                Task { await diagnostics.refresh() }
            }
            .disabled(diagnostics.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryStrip
            Divider()

            if diagnostics.visibleEvents.isEmpty {
                emptyState
            } else {
                List(diagnostics.visibleEvents, id: \.id, selection: selectedEventID) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(levelTitle(event.level))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(levelColor(event.level))
                            Text(categoryTitle(event.category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let duration = event.durationMs {
                                Text("\(duration) ms")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(event.message)
                            .font(.subheadline)
                            .lineLimit(2)

                        Text(event.timestamp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .tag(event.id)
                }
                .listStyle(.plain)
            }
        }
    }

    private var selectedEventID: Binding<String?> {
        Binding(
            get: { diagnostics.selectedEventID },
            set: { selectedID in
                guard let selectedID,
                      let event = diagnostics.visibleEvents.first(where: { $0.id == selectedID })
                else { return }
                diagnostics.select(event)
            }
        )
    }

    private var summaryStrip: some View {
        let summary = diagnostics.summary
        return HStack(spacing: 12) {
            summaryItem(title: "Events", value: "\(summary?.totalCount ?? 0)")
            summaryItem(title: "Warnings", value: "\(summary?.warningCount ?? 0)")
            summaryItem(title: "Errors", value: "\(summary?.errorCount ?? 0)")
            summaryItem(title: "Critical", value: "\(summary?.criticalCount ?? 0)")
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptyStateTitle)
                .font(.headline)
            Text(emptyStateMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyStateTitle: String {
        diagnostics.isLoading ? "Loading diagnostics." : "Diagnostics are recording."
    }

    private var emptyStateMessage: String {
        if diagnostics.isLoading {
            return "Privacy-safe events appear here after app, workflow, toolchain, or command activity."
        }

        return "Privacy-safe events appear here after app, workflow, toolchain, or command activity. Full command output remains in CLI Transcript."
    }

    private var detailPane: some View {
        Group {
            if let event = diagnostics.selectedEvent {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.message)
                                .font(.headline)
                            Text("\(levelTitle(event.level)) / \(categoryTitle(event.category)) / \(event.source)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if event.category == .cli, event.jobId != nil {
                            Button("Open CLI Transcript") {
                                openWindow(id: CliTranscriptWindowView.windowID)
                                diagnostics.openCliTranscript(for: event)
                            }
                        }
                    }

                    detailRows(for: event)

                    Text("Details")
                        .font(.subheadline.weight(.semibold))

                    ScrollView {
                        Text(prettyDetails(event.detailsJson))
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            } else {
                emptyState
            }
        }
    }

    private func detailRows(for event: DiagnosticEventRecord) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            detailRow("Timestamp", event.timestamp)
            detailRow("Privacy", privacyTitle(event.privacy))
            detailRow("Job ID", event.jobId ?? "None")
            detailRow("Command ID", event.commandId ?? "None")
            detailRow("Profile ID", event.profileId ?? "None")
            detailRow("Operation ID", event.operationId ?? "None")
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.footnote)
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func levelTitle(_ level: DiagnosticLevel) -> String {
        switch level {
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        case .critical: "Critical"
        }
    }

    private func categoryTitle(_ category: DiagnosticCategory) -> String {
        switch category {
        case .app: "App"
        case .ui: "UI"
        case .workflow: "Workflow"
        case .engine: "Engine"
        case .cli: "CLI"
        case .database: "Database"
        case .toolchain: "Toolchain"
        case .performance: "Performance"
        case .environment: "Environment"
        }
    }

    private func privacyTitle(_ privacy: DiagnosticPrivacy) -> String {
        switch privacy {
        case .public: "Public"
        case .internal: "Internal"
        case .sensitiveRedacted: "Sensitive Redacted"
        }
    }

    private func levelColor(_ level: DiagnosticLevel) -> Color {
        switch level {
        case .debug, .info: .secondary
        case .warning: .orange
        case .error, .critical: .red
        }
    }

    private func prettyDetails(_ details: String) -> String {
        guard let data = details.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8)
        else {
            return details
        }

        return text
    }
}
