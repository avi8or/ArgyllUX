import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum LogViewerKind: String, Identifiable {
    case error

    var id: String { rawValue }

    var title: String {
        "Error Log"
    }
}

struct LogViewerSheetView: View {
    private static let allSourcesLabel = "All sources"

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let kind: LogViewerKind
    @State private var selectedLevel = LogLevelFilter.errors
    @State private var selectedSource = Self.allSourcesLabel
    @State private var exportDocument = LogExportDocument()
    @State private var isExporting = false
    @State private var statusMessage: String?

    private var filteredEntries: [LogEntry] {
        model.recentLogs.filter { entry in
            selectedLevel.includes(entry.level) &&
                (selectedSource == Self.allSourcesLabel || entry.source == selectedSource)
        }
    }

    private var sourceFilters: [String] {
        let sources = Set(model.recentLogs.map(\.source))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return [Self.allSourcesLabel] + sources
    }

    private var visibleLogText: String {
        filteredEntries.map(Self.exportText(for:)).joined(separator: "\n\n")
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

                Button {
                    Task { await model.refreshLogs(limit: 500) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .padding(20)

            Divider()

            filterBar

            Divider()

            Group {
                if filteredEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No entries match these filters.")
                            .font(.subheadline)
                        Text("Change the level or source filter, or refresh the log.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(filteredEntries.enumerated()), id: \.offset) { _, entry in
                                LogEntryRow(entry: entry)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .textSelection(.enabled)

            Divider()

            HStack(spacing: 10) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    copyVisibleLogText()
                } label: {
                    Label("Copy Visible Text", systemImage: "doc.on.doc")
                }
                .disabled(filteredEntries.isEmpty)

                Button {
                    exportDocument = LogExportDocument(text: visibleLogText)
                    isExporting = true
                } label: {
                    Label("Export TXT", systemImage: "square.and.arrow.down")
                }
                .disabled(filteredEntries.isEmpty)

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
            await model.refreshLogs(limit: 500)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: "ArgyllUX-error-log.txt"
        ) { result in
            switch result {
            case .success:
                statusMessage = "Exported TXT file."
            case let .failure(error):
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Level", selection: $selectedLevel) {
                ForEach(LogLevelFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)

            Picker("Source", selection: $selectedSource) {
                ForEach(sourceFilters, id: \.self) { source in
                    Text(source).tag(source)
                }
            }
            .frame(width: 260)

            Spacer()

            Text("\(filteredEntries.count) shown")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func copyVisibleLogText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(visibleLogText, forType: .string)
        statusMessage = "Copied visible log text."
    }

    private static func exportText(for entry: LogEntry) -> String {
        """
        [\(entry.timestamp)] \(entry.level.uppercased()) \(entry.source)
        \(entry.message)
        """
    }
}

private enum LogLevelFilter: String, CaseIterable, Identifiable {
    case errors
    case warnings
    case info
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .errors:
            "Errors"
        case .warnings:
            "Warnings"
        case .info:
            "Info"
        case .all:
            "All"
        }
    }

    func includes(_ level: String) -> Bool {
        switch self {
        case .errors:
            normalized(level) == "error"
        case .warnings:
            normalized(level) == "warning"
        case .info:
            normalized(level) == "info"
        case .all:
            true
        }
    }

    private func normalized(_ level: String) -> String {
        level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.level.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(levelColor.opacity(0.12), in: Capsule())

                Text(entry.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(entry.timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(entry.message)
                .font(.system(.subheadline, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }

    private var levelColor: Color {
        switch entry.level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "error":
            .red
        case "warning":
            .orange
        default:
            .secondary
        }
    }
}

private struct LogExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
