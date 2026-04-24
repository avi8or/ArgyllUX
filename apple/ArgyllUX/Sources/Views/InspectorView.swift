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
            advancedBody: "Route-specific controls stay in the main work surface. Use this sidebar for guidance, deeper context, and technical details without changing app navigation.",
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
            recommendedBody: detail.nextAction,
            advancedBody: workflowAdvancedCopy(workflow: workflow, detail: detail),
            technicalRows: rows
        )
    }

    private static func shellTechnicalRows(
        appHealth: AppHealth?,
        toolchainStatus: ToolchainStatus?
    ) -> [InspectorDetailRow] {
        [
            InspectorDetailRow(title: "Toolchain", value: technicalToolchainLabel(toolchainStatus)),
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
            "Save the printer, paper, and print-path assumptions before moving into target planning. Context stays attached to this job instead of turning into a separate workflow."
        case .target:
            "Target planning persists in Rust, including Patch Count and whether an existing profile should help target planning."
        case .print:
            "Print keeps unmanaged output explicit and holds the generated target artifacts with the job."
        case .drying:
            "Drying Time is durable. The countdown is a shell convenience, while the printed and ready timestamps live in the engine."
        case .measure:
            detail.measurement.hasMeasurementCheckpoint
                ? "Measurement can resume because checkpoint artifacts were found in the job workspace."
                : "Argyll command output appears in the CLI Transcript window while commands run."
        case .build:
            "Build runs colprof and profcheck in sequence, then stores the first result summary back onto the job."
        case .review, .publish:
            "Review stays explicit. Publishing creates the library record only after you inspect the result."
        case .completed:
            "Completed jobs stay resumable through their linked printer profile, artifacts, and command transcript."
        case .blocked, .failed:
            "A command failed on this job. Argyll command output appears in the CLI Transcript window."
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
