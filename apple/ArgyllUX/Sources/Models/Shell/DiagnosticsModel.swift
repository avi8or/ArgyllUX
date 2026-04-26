import Foundation

enum DiagnosticsLevelFilter: String, CaseIterable, Identifiable {
    case all
    case debug
    case info
    case warning
    case error
    case critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Levels"
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warnings"
        case .error: "Errors"
        case .critical: "Critical"
        }
    }

    var bridgeLevels: [DiagnosticLevel] {
        switch self {
        case .all:
            []
        case .debug:
            [.debug]
        case .info:
            [.info]
        case .warning:
            [.warning]
        case .error:
            [.error]
        case .critical:
            [.critical]
        }
    }
}

enum DiagnosticsCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case app
    case ui
    case workflow
    case engine
    case cli
    case database
    case toolchain
    case performance
    case environment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Categories"
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

    var bridgeCategories: [DiagnosticCategory] {
        switch self {
        case .all: []
        case .app: [.app]
        case .ui: [.ui]
        case .workflow: [.workflow]
        case .engine: [.engine]
        case .cli: [.cli]
        case .database: [.database]
        case .toolchain: [.toolchain]
        case .performance: [.performance]
        case .environment: [.environment]
        }
    }
}

/// Owns diagnostics window state and delegates durable diagnostic storage to
/// the Rust engine through the bridge.
@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published private(set) var summary: DiagnosticsSummary?
    @Published private(set) var visibleEvents: [DiagnosticEventRecord] = []
    @Published private(set) var selectedEventID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var exportMessage: String?
    @Published var levelFilter: DiagnosticsLevelFilter = .all
    @Published var categoryFilter: DiagnosticsCategoryFilter = .all
    @Published var searchText = ""
    @Published var errorsOnly = false

    private let bridge: EngineBridge
    private var refreshRequestID = 0

    var openCliTranscriptRequested: ((String) -> Void)?

    // Tests use this seam to force refresh reentrancy at the point where stale
    // bridge results used to overwrite newer state.
    var refreshResultsReadyForTesting: (() async -> Void)?

    init(bridge: EngineBridge) {
        self.bridge = bridge
    }

    var selectedEvent: DiagnosticEventRecord? {
        guard let selectedEventID else { return nil }
        return visibleEvents.first { $0.id == selectedEventID }
    }

    func refresh(limit: UInt32 = 200) async {
        refreshRequestID += 1
        let requestID = refreshRequestID
        isLoading = true
        let filter = DiagnosticEventFilter(
            levels: levelFilter.bridgeLevels,
            categories: categoryFilter.bridgeCategories,
            searchText: searchText.trimmed.isEmpty ? nil : searchText.trimmed,
            jobId: nil,
            profileId: nil,
            sinceTimestamp: nil,
            untilTimestamp: nil,
            errorsOnly: errorsOnly,
            limit: limit
        )
        let summary = await bridge.getDiagnosticsSummary()
        let events = await bridge.listDiagnosticEvents(filter: filter)

        if let refreshResultsReadyForTesting {
            await refreshResultsReadyForTesting()
        }

        guard requestID == refreshRequestID else { return }

        self.summary = summary
        visibleEvents = events
        if selectedEventID == nil || !events.contains(where: { $0.id == selectedEventID }) {
            selectedEventID = events.first?.id
        }
        isLoading = false
    }

    func select(_ event: DiagnosticEventRecord) {
        selectedEventID = event.id
    }

    func openCliTranscript(for event: DiagnosticEventRecord) {
        guard event.category == .cli, let jobID = event.jobId else { return }
        openCliTranscriptRequested?(jobID)
    }

    func recordUiEvent(source: String, message: String, details: [String: String] = [:], jobID: String? = nil) async {
        let detailsData = (try? JSONSerialization.data(withJSONObject: details, options: [.sortedKeys])) ?? Data("{}".utf8)
        let detailsJSON = String(data: detailsData, encoding: .utf8) ?? "{}"
        _ = await bridge.recordDiagnosticEvent(input: DiagnosticEventInput(
            level: .info,
            category: .ui,
            source: source,
            message: message,
            detailsJson: detailsJSON,
            privacy: .public,
            jobId: jobID,
            commandId: nil,
            profileId: nil,
            issueCaseId: nil,
            durationMs: nil,
            operationId: nil,
            parentOperationId: nil
        ))
    }

    func clearExportMessage() {
        exportMessage = nil
    }
}
