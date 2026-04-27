import SwiftUI

/// Shell-owned utility sidebar for route and workflow guidance.
enum InspectorTab: String, CaseIterable, Identifiable {
    case recommended = "Recommended"
    case advanced = "Advanced"
    case technical = "Technical"

    var id: String { rawValue }
}

struct InspectorDetailRow: Identifiable, Hashable {
    let title: String
    let value: String

    var id: String { title }
}

struct InspectorContent: Hashable {
    let recommendedBody: String
    let advancedBody: String
    let technicalRows: [InspectorDetailRow]

    static func route(
        route: AppRoute,
        appHealth: AppHealth?,
        toolchainStatus: ToolchainStatus?
    ) -> InspectorContent {
        InspectorContent(
            recommendedBody: route.inspectorNote,
            advancedBody: route.advancedInspectorNote,
            technicalRows: shellTechnicalRows(appHealth: appHealth, toolchainStatus: toolchainStatus)
        )
    }

    static func openingWorkflow(
        appHealth: AppHealth?,
        toolchainStatus: ToolchainStatus?
    ) -> InspectorContent {
        InspectorContent(
            recommendedBody: "Opening New Profile.",
            advancedBody: "Workflow context will appear after the job detail loads.",
            technicalRows: shellTechnicalRows(appHealth: appHealth, toolchainStatus: toolchainStatus)
        )
    }

    @MainActor
    static func workflow(
        workflow: NewProfileWorkflowModel,
        detail: NewProfileJobDetail,
        appHealth: AppHealth?,
        toolchainStatus: ToolchainStatus?
    ) -> InspectorContent {
        var rows = [
            InspectorDetailRow(title: "Stage", value: workflowStageTitle(detail.stage)),
            InspectorDetailRow(title: "Workspace", value: detail.workspacePath),
            InspectorDetailRow(title: "Measurement Mode", value: workflowMeasurementModeLabel(workflow.workflowMeasurementMode)),
            InspectorDetailRow(title: "Command state", value: detail.isCommandRunning ? "Running" : "Idle"),
        ]

        if detail.measurement.hasMeasurementCheckpoint {
            rows.append(InspectorDetailRow(title: "Measurement checkpoint", value: "Available"))
        }

        if let latestError = detail.latestError {
            rows.append(InspectorDetailRow(title: "Latest error", value: latestError))
        }

        rows.append(contentsOf: shellTechnicalRows(appHealth: appHealth, toolchainStatus: toolchainStatus))

        return InspectorContent(
            recommendedBody: workflowNextActionDisplayTitle(detail),
            advancedBody: workflowAdvancedCopy(workflow: workflow, detail: detail),
            technicalRows: rows
        )
    }

    private static func shellTechnicalRows(
        appHealth: AppHealth?,
        toolchainStatus: ToolchainStatus?
    ) -> [InspectorDetailRow] {
        [
            InspectorDetailRow(title: "Argyll", value: technicalToolchainLabel(toolchainStatus)),
            InspectorDetailRow(
                title: "Last validation",
                value: toolchainStatus?.lastValidationTime ?? "Waiting for validation"
            ),
            InspectorDetailRow(title: "Readiness", value: appHealth?.readiness.capitalized ?? "Blocked"),
        ]
    }

    private static func technicalToolchainLabel(_ toolchainStatus: ToolchainStatus?) -> String {
        switch toolchainStatus?.state {
        case .ready:
            "Ready"
        case .partial:
            "Partial"
        case .notFound, .none:
            "Not Found"
        }
    }

    @MainActor
    private static func workflowAdvancedCopy(
        workflow: NewProfileWorkflowModel,
        detail: NewProfileJobDetail
    ) -> String {
        switch workflow.effectiveWorkflowStage {
        case .context:
            "Choose the printer, paper, print settings, and measurement setup before target planning."
        case .target:
            "Keep the default patch count unless you have a reason to spend more print and measurement time."
        case .print:
            "Print the generated target without color management. Managed target output will produce a bad profile."
        case .drying:
            "Wait for the print to stabilize before measuring, especially on fine-art or high-ink papers."
        case .measure:
            detail.measurement.hasMeasurementCheckpoint
                ? "Resume the measurement from the saved checkpoint, or open the transcript if you need command detail."
                : "Measure the target when the instrument and printed chart are ready."
        case .build:
            "Build the profile from the measured chart only after the measurement source is available."
        case .review, .publish:
            "Review the first result before publishing it into Printer Profiles."
        case .completed:
            "Open the published profile to review trust, linked measurements, and follow-up actions."
        case .blocked, .failed:
            "Open the CLI Transcript for command output, then fix the blocking condition before retrying."
        }
    }
}

struct InspectorView: View {
    let content: InspectorContent
    @State private var selectedTab: InspectorTab = .recommended

    var body: some View {
        VStack(spacing: 0) {
            Picker("Utility sidebar section", selection: $selectedTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(16)

            Divider()

            ScrollView {
                tabContent
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.04))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .recommended:
            inspectorSection(title: InspectorTab.recommended.rawValue, body: content.recommendedBody)
        case .advanced:
            inspectorSection(title: InspectorTab.advanced.rawValue, body: content.advancedBody)
        case .technical:
            VStack(alignment: .leading, spacing: 12) {
                Text(InspectorTab.technical.rawValue)
                    .font(.headline)

                ForEach(content.technicalRows) { row in
                    OperationalDetailRow(title: row.title, value: row.value)
                }
            }
        }
    }

    private func inspectorSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

}
