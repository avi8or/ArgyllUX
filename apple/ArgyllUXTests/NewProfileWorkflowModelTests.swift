import Foundation
import Testing
@testable import ArgyllUX

@MainActor
struct NewProfileWorkflowModelTests {
    @Test
    func primaryActionPresentationExplainsDisabledProfileSetup() async {
        let fakeEngine = FakeEngine()
        let detail = makeJobDetail(stage: .context, nextAction: "Save Context")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: detail.id)])
        fakeEngine.loadedJobDetails[detail.id] = detail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()

        model.workflowProfileName = ""
        model.workflowSelectedPrinterID = nil
        model.workflowSelectedPaperID = nil

        let presentation = model.workflowPrimaryActionPresentation

        #expect(presentation.title == "Continue")
        #expect(presentation.isEnabled == false)
        #expect(presentation.disabledReason == "Name the profile, choose a printer and paper, and choose printer and paper settings to continue.")
    }

    @Test
    func primaryActionPresentationRequiresUnmanagedPrintConfirmation() async {
        let fakeEngine = FakeEngine()
        let detail = makeJobDetail(stage: .print, nextAction: "Mark Chart as Printed")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: detail.id, stage: .print)])
        fakeEngine.loadedJobDetails[detail.id] = detail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()
        model.workflowPrintWithoutColorManagement = false

        let presentation = model.workflowPrimaryActionPresentation

        #expect(presentation.title == "Mark Chart as Printed")
        #expect(presentation.isEnabled == false)
        #expect(presentation.disabledReason == "Confirm that the target was printed without color management before marking it printed.")
    }

    @Test
    func savePrintSettingsDoesNotPersistManagedTargetOutput() async {
        let fakeEngine = FakeEngine()
        let detail = makeJobDetail(stage: .print, nextAction: "Mark Chart as Printed")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: detail.id, stage: .print)])
        fakeEngine.loadedJobDetails[detail.id] = detail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()
        model.workflowPrintWithoutColorManagement = false

        await model.savePrintSettings()

        #expect(fakeEngine.lastSavePrintSettingsInput == nil)
    }

    @Test
    func primaryActionPresentationExplainsMissingScanFile() async {
        let fakeEngine = FakeEngine()
        let detail = makeJobDetail(stage: .measure, nextAction: "Measure")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: detail.id)])
        fakeEngine.loadedJobDetails[detail.id] = detail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        await model.openNewProfileWorkflow()

        model.workflowMeasurementMode = .scanFile
        model.workflowScanFilePath = ""

        let presentation = model.workflowPrimaryActionPresentation

        #expect(presentation.title == "Measure")
        #expect(presentation.isEnabled == false)
        #expect(presentation.disabledReason == "Choose a scan file before measuring from a file.")
    }

    @Test
    func openNewProfileWorkflowSettingsHandoffResumesExistingActiveJobWithoutCreatingDuplicate() async {
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(
            stage: .context,
            nextAction: "Save Context",
            printer: printer,
            paper: paper
        )

        let fakeEngine = FakeEngine()
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.loadedJobDetails[draftDetail.id] = draftDetail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        model.applyReferenceData(makeReferenceData(printers: [printer], papers: [paper]))

        await model.openNewProfileWorkflow(printerId: printer.id, paperId: paper.id)

        #expect(fakeEngine.resolveNewProfileLaunchCallCount == 1)
        #expect(fakeEngine.createDraftCallCount == 0)
        #expect(fakeEngine.lastResolveNewProfileLaunchInput?.printerId == printer.id)
        #expect(fakeEngine.lastResolveNewProfileLaunchInput?.paperId == paper.id)
        #expect(fakeEngine.lastCreateDraftInput?.printerId == nil)
        #expect(fakeEngine.lastCreateDraftInput?.paperId == nil)
        #expect(model.activeNewProfileDetail?.id == draftDetail.id)
        #expect(model.workflowProfileName == draftDetail.profileName)
        #expect(model.workflowSelectedPrinterID == printer.id)
        #expect(model.workflowSelectedPaperID == paper.id)
        #expect(model.printers.map(\.id) == [printer.id])
        #expect(model.papers.map(\.id) == [paper.id])
    }

    @Test
    func openNewProfileWorkflowCreatesSeededDraftWhenNoResumableJobExists() async {
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        model.applyReferenceData(makeReferenceData(printers: [printer], papers: [paper]))

        await model.openNewProfileWorkflow(printerId: printer.id, paperId: paper.id)

        #expect(fakeEngine.resolveNewProfileLaunchCallCount == 1)
        #expect(fakeEngine.createDraftCallCount == 1)
        #expect(fakeEngine.lastResolveNewProfileLaunchInput?.printerId == printer.id)
        #expect(fakeEngine.lastResolveNewProfileLaunchInput?.paperId == paper.id)
        #expect(fakeEngine.lastCreateDraftInput?.printerId == printer.id)
        #expect(fakeEngine.lastCreateDraftInput?.paperId == paper.id)
        #expect(model.activeNewProfileDetail?.id == draftDetail.id)
    }

    @Test
    func saveWorkflowContextPersistsSelectedPrinterAndPaper() async {
        let printer = makePrinter()
        let paper = makePaper()
        let preset = makePreset(printerId: printer.id, paperId: paper.id)
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper, preset: preset)
        let savedDetail = makeJobDetail(stage: .target, nextAction: "Generate Target", printer: printer, paper: paper, preset: preset)

        let fakeEngine = FakeEngine()
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.printerPaperPresetsCurrent = [preset]
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.createNewProfileDraftResult = draftDetail
        fakeEngine.saveNewProfileContextResult = savedDetail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        model.applyReferenceData(
            makeReferenceData(
                printers: [printer],
                papers: [paper],
                printerPaperPresets: [preset]
            )
        )

        await model.openNewProfileWorkflow()

        model.workflowProfileName = "P900 Rag v1"
        model.workflowPrintPath = preset.printPath
        model.workflowPrintPathNotes = "Rear tray"
        model.workflowMeasurementNotes = "Warm up the instrument."
        model.workflowMeasurementObserver = "2"
        model.workflowMeasurementIlluminant = "D50"
        model.workflowMeasurementMode = .patch

        await model.saveWorkflowContext()

        #expect(fakeEngine.lastSaveContextInput?.jobId == draftDetail.id)
        #expect(fakeEngine.lastSaveContextInput?.printerId == printer.id)
        #expect(fakeEngine.lastSaveContextInput?.paperId == paper.id)
        #expect(fakeEngine.lastSaveContextInput?.printerPaperPresetId == preset.id)
        #expect(fakeEngine.lastSaveContextInput?.printPath == preset.printPath)
        #expect(fakeEngine.lastSaveContextInput?.measurementMode == .patch)
        #expect(model.activeNewProfileDetail?.stage == .target)
        #expect(model.workflowPatchCount == "928")
    }

    @Test
    func createWorkflowPresetSelectsNewPresetInline() async {
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        model.applyReferenceData(makeReferenceData(printers: [printer], papers: [paper]))

        await model.openNewProfileWorkflow()

        model.beginWorkflowPresetCreation()
        model.workflowPresetDraft.label = "Studio Matte"
        model.workflowPresetDraft.printPath = "Mirage"
        model.workflowPresetDraft.mediaSetting = "Premium Luster"
        model.workflowPresetDraft.qualityMode = "1440 dpi"
        model.workflowPresetDraft.totalInkLimitPercentText = "280"
        model.workflowPresetDraft.blackInkLimitPercentText = "90"

        await model.createWorkflowPreset()

        #expect(fakeEngine.lastCreatedPresetInput?.printerId == printer.id)
        #expect(fakeEngine.lastCreatedPresetInput?.paperId == paper.id)
        #expect(fakeEngine.lastCreatedPresetInput?.printPath == "Mirage")
        #expect(model.workflowSelectedPrinterPaperPreset?.label == "Studio Matte")
        #expect(model.workflowSelectedPrinterPaperPreset?.printPath == "Mirage")
        #expect(model.workflowSelectedPrinterPaperPreset?.mediaSetting == "Premium Luster")
        #expect(model.workflowSelectedPrinterPaperPreset?.qualityMode == "1440 dpi")
    }

    @Test
    func beginWorkflowPresetCreationOpensModalAndSeedsLegacyWorkflowValues() async {
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(
            stage: .context,
            nextAction: "Save Context",
            printer: printer,
            paper: paper,
            printPath: "Photoshop -> Canon driver"
        )

        let fakeEngine = FakeEngine()
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        model.applyReferenceData(makeReferenceData(printers: [printer], papers: [paper]))

        await model.openNewProfileWorkflow()

        #expect(model.showsWorkflowStandalonePrintPathEditor)

        model.beginWorkflowPresetCreation()

        #expect(model.workflowContextSheet == .newPreset)
        #expect(model.showsWorkflowStandalonePrintPathEditor)
        #expect(model.workflowPresetDraft.printerId == printer.id)
        #expect(model.workflowPresetDraft.paperId == paper.id)
        #expect(model.workflowPresetDraft.printPath == "Photoshop -> Canon driver")
        #expect(model.workflowPresetDraft.mediaSetting == "Premium Luster")
        #expect(model.workflowPresetDraft.qualityMode == "1440 dpi")
    }

    @Test
    func choosingWorkflowPrinterDismissesChooserSheet() async {
        let printer = makePrinter()
        let alternatePrinter = makeAlternatePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer, alternatePrinter]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        model.applyReferenceData(makeReferenceData(printers: [printer, alternatePrinter], papers: [paper]))

        await model.openNewProfileWorkflow()

        model.presentWorkflowPrinterChooser()
        #expect(model.workflowContextSheet == .choosePrinter)
        model.selectWorkflowPrinter(alternatePrinter.id)

        #expect(model.workflowContextSheet == nil)
        #expect(model.workflowSelectedPrinterID == alternatePrinter.id)
    }

    @Test
    func dismissWorkflowContextSheetResetsPresetDraft() async {
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        model.applyReferenceData(makeReferenceData(printers: [printer], papers: [paper]))

        await model.openNewProfileWorkflow()

        model.beginWorkflowPresetCreation()
        model.workflowPresetDraft.label = "Temporary"
        model.workflowPresetDraft.printPath = "Mirage"

        model.dismissWorkflowContextSheet()

        #expect(model.workflowContextSheet == nil)
        #expect(model.workflowPresetDraft == PrinterPaperPresetDraft())
    }

    @Test
    func createWorkflowPresetPersistsCurrentPairAfterSelectionChanges() async {
        let printer = makePrinter()
        let alternatePrinter = makeAlternatePrinter()
        let paper = makePaper()
        let alternatePaper = makeAlternatePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer, alternatePrinter]
        fakeEngine.papersCurrent = [paper, alternatePaper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        model.applyReferenceData(makeReferenceData(printers: [printer, alternatePrinter], papers: [paper, alternatePaper]))

        await model.openNewProfileWorkflow()

        model.selectWorkflowPrinter(alternatePrinter.id)
        model.selectWorkflowPaper(alternatePaper.id)

        model.beginWorkflowPresetCreation()
        model.workflowPresetDraft.label = "Alternate path"
        model.workflowPresetDraft.printPath = "Mirage"
        model.workflowPresetDraft.mediaSetting = "Fine Art Smooth"
        model.workflowPresetDraft.qualityMode = "High"

        await model.createWorkflowPreset()

        #expect(fakeEngine.lastCreatedPresetInput?.printerId == alternatePrinter.id)
        #expect(fakeEngine.lastCreatedPresetInput?.paperId == alternatePaper.id)
        #expect(fakeEngine.lastCreatedPresetInput?.printPath == "Mirage")
        #expect(model.workflowSelectedPrinterPaperPreset?.printerId == alternatePrinter.id)
        #expect(model.workflowSelectedPrinterPaperPreset?.paperId == alternatePaper.id)
    }

    @Test
    func legacyWorkflowContextKeepsSnapshottedMediaAndQualityWithoutPreset() async {
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = makeWorkflowModel(fakeEngine: fakeEngine)
        model.applyReferenceData(makeReferenceData(printers: [printer], papers: [paper]))

        await model.openNewProfileWorkflow()

        #expect(model.workflowHasLegacyContextWithoutPreset)
        #expect(model.workflowSelectedPrinterPaperPresetID == nil)
        #expect(model.workflowPrintPath.isEmpty)
        #expect(model.workflowMediaSetting == "Premium Luster")
        #expect(model.workflowQualityMode == "1440 dpi")
    }
}
