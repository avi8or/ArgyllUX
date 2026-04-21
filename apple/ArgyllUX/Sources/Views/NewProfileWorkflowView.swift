import SwiftUI

struct NewProfileWorkflowActions {
    let performPrimaryAction: () -> Void
    let requestWorkflowDeletion: () -> Void
    let openCliTranscript: (String) -> Void
    let saveContext: () -> Void
    let createWorkflowPrinter: () -> Void
    let createWorkflowPaper: () -> Void
    let createWorkflowPreset: () -> Void
    let saveTargetSettings: () -> Void
    let generateTarget: () -> Void
    let savePrintSettings: () -> Void
    let markChartPrinted: () -> Void
    let markReadyToMeasure: () -> Void
    let startMeasurement: () -> Void
    let buildProfile: () -> Void
    let publishProfile: () -> Void
    let openPublishedProfileLibrary: () -> Void
}

struct NewProfileWorkflowView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    @ObservedObject var transcript: CliTranscriptModel
    let actions: NewProfileWorkflowActions

    var body: some View {
        Group {
            if let detail = workflow.activeNewProfileDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        NewProfileWorkflowHeaderView(workflow: workflow, detail: detail, actions: actions)

                        HStack(alignment: .top, spacing: 18) {
                            NewProfileWorkflowTimelineView(detail: detail)
                                .frame(width: 220)

                            NewProfileWorkflowWorkspaceView(
                                workflow: workflow,
                                detail: detail,
                                actions: actions
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                            NewProfileWorkflowInspectorView(workflow: workflow, detail: detail)
                                .frame(width: 280)
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ProgressView("Opening New Profile")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
