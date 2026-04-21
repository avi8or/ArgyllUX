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
                VStack(spacing: 0) {
                    NewProfileWorkflowHeaderView(workflow: workflow, detail: detail, actions: actions)

                    Divider()

                    HStack(spacing: 0) {
                        ScrollView {
                            NewProfileWorkflowWorkspaceView(
                                workflow: workflow,
                                detail: detail,
                                actions: actions
                            )
                            .padding(24)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        Divider()

                        ScrollView {
                            NewProfileWorkflowSidebarView(workflow: workflow, detail: detail)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(minWidth: 320, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.secondary.opacity(0.04))
                    }
                }
                .sheet(item: $workflow.workflowContextSheet) { sheet in
                    contextSheetView(for: sheet)
                }
            } else {
                ProgressView("Opening New Profile")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func contextSheetView(for sheet: WorkflowContextSheet) -> some View {
        switch sheet {
        case .choosePrinter:
            WorkflowPrinterChooserSheet(workflow: workflow)
        case .newPrinter, .editPrinter:
            PrinterEditorForm(
                title: workflow.workflowPrinterDraft.title,
                draft: $workflow.workflowPrinterDraft,
                saveTitle: workflow.workflowPrinterDraft.id == nil ? "Save Printer" : "Save Changes",
                secondaryTitle: "Cancel",
                isSaveDisabled: !workflow.isWorkflowPrinterDraftValid,
                onSave: actions.createWorkflowPrinter,
                onSecondary: {
                    workflow.dismissWorkflowContextSheet()
                }
            )
        case .choosePaper:
            WorkflowPaperChooserSheet(workflow: workflow)
        case .newPaper, .editPaper:
            PaperEditorForm(
                title: workflow.workflowPaperDraft.title,
                draft: $workflow.workflowPaperDraft,
                saveTitle: workflow.workflowPaperDraft.id == nil ? "Save Paper" : "Save Changes",
                secondaryTitle: "Cancel",
                isSaveDisabled: !workflow.isWorkflowPaperDraftValid,
                onSave: actions.createWorkflowPaper,
                onSecondary: {
                    workflow.dismissWorkflowContextSheet()
                }
            )
        case .newPreset, .editPreset:
            PrinterPaperPresetEditorForm(
                title: workflow.workflowPresetDraft.title,
                draft: $workflow.workflowPresetDraft,
                printers: workflow.printers,
                papers: workflow.papers,
                lockPrinterAndPaperSelection: true,
                saveTitle: workflow.workflowPresetDraft.id == nil ? "Save Settings" : "Save Changes",
                secondaryTitle: "Cancel",
                isSaveDisabled: !workflow.isWorkflowPresetDraftValid,
                onSave: actions.createWorkflowPreset,
                onSecondary: {
                    workflow.dismissWorkflowContextSheet()
                }
            )
        }
    }
}
