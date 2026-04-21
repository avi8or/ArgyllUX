import Foundation
import Testing
@testable import ArgyllUX

@MainActor
struct AppModelTests {
    @Test
    func bootstrapLoadsToolchainHealthAndDashboardSnapshot() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.bootstrapStatusValue = BootstrapStatus(
            appSupportDirReady: true,
            databaseInitialized: true,
            migrationsApplied: true,
            toolchainStatus: fakeEngine.toolchainStatusValue
        )
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])
        fakeEngine.appHealthValue = AppHealth(
            readiness: "ready",
            blockingIssues: [],
            warnings: ["Storage location: /tmp/ArgyllUX"]
        )
        fakeEngine.logsValue = [
            LogEntry(
                timestamp: "2026-04-19T18:30:00Z",
                level: "info",
                message: "Bootstrap completed.",
                source: "engine.bootstrap"
            )
        ]

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.bootstrapIfNeeded()

        #expect(fakeEngine.bootstrapCallCount == 1)
        #expect(model.toolchainStatus?.state == .ready)
        #expect(model.toolchainStatus?.argyllVersion == "3.5.0")
        #expect(model.appHealth?.readiness == "ready")
        #expect(model.jobsCount == 0)
        #expect(model.detectedToolchainPath == "/opt/homebrew/bin")
        #expect(model.recentLogs.isEmpty)
        #expect(model.toolchainPathInput == "/opt/homebrew/bin")
    }

    @Test
    func openNewProfileWorkflowSettingsHandoffResumesExistingActiveJobWithoutCreatingDuplicate() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(
            stage: .context,
            nextAction: "Save Context",
            printer: printer,
            paper: paper
        )

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.bootstrapStatusValue = BootstrapStatus(
            appSupportDirReady: true,
            databaseInitialized: true,
            migrationsApplied: true,
            toolchainStatus: fakeEngine.toolchainStatusValue
        )
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail
        fakeEngine.loadedJobDetails[draftDetail.id] = draftDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow(printerId: printer.id, paperId: paper.id)

        #expect(fakeEngine.createDraftCallCount == 0)
        #expect(fakeEngine.lastCreateDraftInput?.printerId == nil)
        #expect(fakeEngine.lastCreateDraftInput?.paperId == nil)
        #expect(model.isShowingNewProfileWorkflow)
        #expect(model.activeNewProfileDetail?.id == draftDetail.id)
        #expect(model.workflowProfileName == draftDetail.profileName)
        #expect(model.workflowSelectedPrinterID == printer.id)
        #expect(model.workflowSelectedPaperID == paper.id)
        #expect(model.printers.map(\.id) == [printer.id])
        #expect(model.papers.map(\.id) == [paper.id])
    }

    @Test
    func openNewProfileWorkflowCreatesSeededDraftWhenNoResumableJobExists() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow(printerId: printer.id, paperId: paper.id)

        #expect(fakeEngine.createDraftCallCount == 1)
        #expect(fakeEngine.lastCreateDraftInput?.printerId == printer.id)
        #expect(fakeEngine.lastCreateDraftInput?.paperId == paper.id)
        #expect(model.activeNewProfileDetail?.id == draftDetail.id)
    }

    @Test
    func confirmActiveWorkDeletionClearsDeletedJob() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context")
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.loadedJobDetails[draftDetail.id] = draftDetail
        fakeEngine.deleteNewProfileJobResult = DeleteResult(success: true, message: "")

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()
        await model.openCliTranscript(jobId: draftDetail.id)
        model.requestActiveWorkDeletion(makeActiveWorkItem(id: draftDetail.id))
        await model.confirmPendingDeletion()

        #expect(fakeEngine.lastDeletedJobId == draftDetail.id)
        #expect(model.activeNewProfileDetail == nil)
        #expect(model.activeWorkItems.isEmpty)
        #expect(model.deletionErrorMessage == nil)

        guard case let .deleted(jobTitle) = model.cliTranscriptState else {
            Issue.record("Expected the transcript window to move into the deleted-job state.")
            return
        }

        #expect(jobTitle == draftDetail.title)
        #expect(model.cliTranscriptTarget == .job(jobId: draftDetail.id))
    }

    @Test
    func openCliTranscriptKeepsExplicitJobWhenAnotherResumableJobIsNewer() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let currentDetail = makeJobDetail(
            id: "job-1",
            title: "P900 Rag v1",
            stage: .context,
            nextAction: "Save Context"
        )
        let newerDetail = makeJobDetail(
            id: "job-2",
            title: "P900 Rag v2",
            stage: .target,
            nextAction: "Generate Target"
        )

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: currentDetail.id, title: currentDetail.title)])
        fakeEngine.loadedJobDetails[currentDetail.id] = currentDetail
        fakeEngine.loadedJobDetails[newerDetail.id] = newerDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()

        fakeEngine.dashboardSnapshotCurrent = makeDashboard(
            activeWorkItems: [
                makeActiveWorkItem(id: newerDetail.id, title: newerDetail.title, nextAction: newerDetail.nextAction, stage: newerDetail.stage),
                makeActiveWorkItem(id: currentDetail.id, title: currentDetail.title, nextAction: currentDetail.nextAction, stage: currentDetail.stage)
            ]
        )

        await model.openCliTranscript(jobId: currentDetail.id)

        #expect(model.activeNewProfileDetail?.id == currentDetail.id)
        #expect(model.cliTranscriptDetail?.id == currentDetail.id)
        #expect(model.cliTranscriptTarget == .job(jobId: currentDetail.id))
    }

    @Test
    func openLatestCliTranscriptLoadsLatestResumableJobWithoutRetargetingWorkflow() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let currentDetail = makeJobDetail(
            id: "job-1",
            title: "P900 Rag v1",
            stage: .context,
            nextAction: "Save Context"
        )
        let newerDetail = makeJobDetail(
            id: "job-2",
            title: "P900 Rag v2",
            stage: .target,
            nextAction: "Generate Target"
        )

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: currentDetail.id, title: currentDetail.title)])
        fakeEngine.loadedJobDetails[currentDetail.id] = currentDetail
        fakeEngine.loadedJobDetails[newerDetail.id] = newerDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()

        fakeEngine.dashboardSnapshotCurrent = makeDashboard(
            activeWorkItems: [
                makeActiveWorkItem(id: newerDetail.id, title: newerDetail.title, nextAction: newerDetail.nextAction, stage: newerDetail.stage),
                makeActiveWorkItem(id: currentDetail.id, title: currentDetail.title, nextAction: currentDetail.nextAction, stage: currentDetail.stage)
            ]
        )

        await model.openLatestCliTranscript()

        #expect(model.activeNewProfileDetail?.id == currentDetail.id)
        #expect(model.cliTranscriptDetail?.id == newerDetail.id)
        #expect(model.cliTranscriptTarget == .latestResumable(jobId: newerDetail.id))
    }

    @Test
    func confirmActiveWorkDeletionKeepsShellTranscriptTargetAfterFooterSelection() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let currentDetail = makeJobDetail(
            id: "job-1",
            title: "P900 Rag v1",
            stage: .context,
            nextAction: "Save Context"
        )
        let newerDetail = makeJobDetail(
            id: "job-2",
            title: "P900 Rag v2",
            stage: .target,
            nextAction: "Generate Target"
        )

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(
            activeWorkItems: [
                makeActiveWorkItem(id: newerDetail.id, title: newerDetail.title, nextAction: newerDetail.nextAction, stage: newerDetail.stage),
                makeActiveWorkItem(id: currentDetail.id, title: currentDetail.title, nextAction: currentDetail.nextAction, stage: currentDetail.stage)
            ]
        )
        fakeEngine.loadedJobDetails[currentDetail.id] = currentDetail
        fakeEngine.loadedJobDetails[newerDetail.id] = newerDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openLatestCliTranscript()
        model.requestActiveWorkDeletion(makeActiveWorkItem(id: newerDetail.id, title: newerDetail.title, nextAction: newerDetail.nextAction, stage: newerDetail.stage))
        await model.confirmPendingDeletion()

        guard case let .deleted(jobTitle) = model.cliTranscriptState else {
            Issue.record("Expected the transcript window to move into the deleted-job state.")
            return
        }

        #expect(jobTitle == newerDetail.title)
        #expect(model.cliTranscriptTarget == .latestResumable(jobId: newerDetail.id))
    }

    @Test
    func confirmActiveWorkDeletionFailureKeepsLoadedJobAndShowsError() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context")
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.loadedJobDetails[draftDetail.id] = draftDetail
        fakeEngine.deleteNewProfileJobResult = DeleteResult(success: false, message: "Database is locked.")

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()
        model.requestActiveWorkDeletion(makeActiveWorkItem(id: draftDetail.id))
        await model.confirmPendingDeletion()

        #expect(model.activeNewProfileDetail?.id == draftDetail.id)
        #expect(model.activeWorkItems.map(\.id) == [draftDetail.id])
        #expect(model.deletionErrorMessage == "Database is locked.")
    }

    @Test
    func openLatestCliTranscriptShowsEmptyStateWhenNoResumableJobExists() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openLatestCliTranscript()

        guard case .empty = model.cliTranscriptState else {
            Issue.record("Expected the transcript window to show the empty shell-level state.")
            return
        }
    }

    @Test
    func saveWorkflowContextPersistsSelectedPrinterAndPaper() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let printer = makePrinter()
        let paper = makePaper()
        let preset = makePreset(printerId: printer.id, paperId: paper.id)
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper, preset: preset)
        let savedDetail = makeJobDetail(stage: .target, nextAction: "Generate Target", printer: printer, paper: paper, preset: preset)

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.appHealthValue = AppHealth(readiness: "ready", blockingIssues: [], warnings: [])
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.printerPaperPresetsCurrent = [preset]
        fakeEngine.createNewProfileDraftResult = draftDetail
        fakeEngine.saveNewProfileContextResult = savedDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
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
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
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
    func beginWorkflowPresetCreationSeedsLegacyWorkflowValues() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
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
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()

        #expect(model.showsWorkflowStandalonePrintPathEditor)

        model.beginWorkflowPresetCreation()

        #expect(model.showWorkflowPresetForm)
        #expect(!model.showsWorkflowStandalonePrintPathEditor)
        #expect(model.workflowPresetDraft.printerId == printer.id)
        #expect(model.workflowPresetDraft.paperId == paper.id)
        #expect(model.workflowPresetDraft.printPath == "Photoshop -> Canon driver")
        #expect(model.workflowPresetDraft.mediaSetting == "Premium Luster")
        #expect(model.workflowPresetDraft.qualityMode == "1440 dpi")
    }

    @Test
    func changingWorkflowPairWhileCreatingPresetSyncsDraftAndSanitizesPrinterFields() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let printer = makePrinter()
        let alternatePrinter = makeAlternatePrinter()
        let paper = makePaper()
        let alternatePaper = makeAlternatePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer, alternatePrinter]
        fakeEngine.papersCurrent = [paper, alternatePaper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()

        model.beginWorkflowPresetCreation()
        model.workflowPresetDraft.label = "Studio Matte"
        model.workflowPresetDraft.printPath = "Mirage"
        model.workflowPresetDraft.notes = "Keep this note."
        model.workflowPresetDraft.mediaSetting = "Premium Luster"
        model.workflowPresetDraft.qualityMode = "1440 dpi"
        model.workflowPresetDraft.blackInkLimitPercentText = "90"

        model.selectWorkflowPrinter(alternatePrinter.id)

        #expect(model.showWorkflowPresetForm)
        #expect(model.workflowPresetDraft.printerId == alternatePrinter.id)
        #expect(model.workflowPresetDraft.paperId == paper.id)
        #expect(model.workflowPresetDraft.label == "Studio Matte")
        #expect(model.workflowPresetDraft.printPath == "Mirage")
        #expect(model.workflowPresetDraft.notes == "Keep this note.")
        #expect(model.workflowPresetDraft.mediaSetting.isEmpty)
        #expect(model.workflowPresetDraft.qualityMode.isEmpty)
        #expect(model.workflowPresetDraft.blackInkLimitPercentText.isEmpty)

        model.selectWorkflowPaper(alternatePaper.id)

        #expect(model.workflowPresetDraft.paperId == alternatePaper.id)
    }

    @Test
    func clearingWorkflowPrinterWhileCreatingPresetCancelsInlinePresetDraft() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()

        model.beginWorkflowPresetCreation()
        model.workflowPresetDraft.label = "Temporary"

        model.selectWorkflowPrinter(nil)

        #expect(!model.showWorkflowPresetForm)
        #expect(model.workflowPresetDraft == PrinterPaperPresetDraft())
    }

    @Test
    func createWorkflowPresetPersistsCurrentPairAfterSelectionChanges() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let printer = makePrinter()
        let alternatePrinter = makeAlternatePrinter()
        let paper = makePaper()
        let alternatePaper = makeAlternatePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer, alternatePrinter]
        fakeEngine.papersCurrent = [paper, alternatePaper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()

        model.beginWorkflowPresetCreation()
        model.workflowPresetDraft.label = "Alternate path"
        model.workflowPresetDraft.printPath = "Mirage"

        model.selectWorkflowPrinter(alternatePrinter.id)
        model.selectWorkflowPaper(alternatePaper.id)

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
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let printer = makePrinter()
        let paper = makePaper()
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()

        #expect(model.workflowHasLegacyContextWithoutPreset)
        #expect(model.workflowSelectedPrinterPaperPresetID == nil)
        #expect(model.workflowPrintPath.isEmpty)
        #expect(model.workflowMediaSetting == "Premium Luster")
        #expect(model.workflowQualityMode == "1440 dpi")
    }

    @Test
    func catalogEntryDraftIgnoresWhitespaceOnlyValues() {
        var draft = CatalogEntryDraft(pendingValue: "   ")
        var values = ["Existing"]

        let committed = draft.commit(into: &values)

        #expect(!committed)
        #expect(values == ["Existing"])
        #expect(draft.pendingValue == "   ")
    }

    @Test
    func catalogEntryDraftAppendsTrimmedValueAndClearsPendingText() {
        var draft = CatalogEntryDraft(pendingValue: "  Premium Luster  ")
        var values: [String] = []

        let committed = draft.commit(into: &values)

        #expect(committed)
        #expect(values == ["Premium Luster"])
        #expect(draft.pendingValue.isEmpty)
    }

    @Test
    func editPaperLoadsStructuredPaperFields() {
        let model = AppModel(engine: FakeEngine())

        model.editPaper(makePaper())

        #expect(model.settingsPaperDraft.manufacturer == "Canson")
        #expect(model.settingsPaperDraft.paperLine == "Rag Photographique")
        #expect(model.settingsPaperDraft.surfaceClassSelection == "Matte")
        #expect(model.settingsPaperDraft.basisWeightValue == "310")
        #expect(model.settingsPaperDraft.basisWeightUnit == .gsm)
        #expect(model.settingsPaperDraft.thicknessValue == "15.7")
        #expect(model.settingsPaperDraft.thicknessUnit == .mil)
        #expect(model.settingsPaperDraft.surfaceTexture == "Smooth")
        #expect(model.settingsPaperDraft.baseMaterial == "Cotton rag")
        #expect(model.settingsPaperDraft.mediaColor == "White")
        #expect(model.settingsPaperDraft.obaContent == "Low OBA")
        #expect(model.settingsPaperDraft.inkCompatibility == "Pigment")
    }

    @Test
    func saveSettingsPaperUsesStructuredPaperInput() async {
        let fakeEngine = FakeEngine()
        let model = AppModel(engine: fakeEngine)

        model.settingsPaperDraft.manufacturer = "Hahnemuhle"
        model.settingsPaperDraft.paperLine = "Photo Rag"
        model.settingsPaperDraft.surfaceClassSelection = "Matte"
        model.settingsPaperDraft.basisWeightValue = "308"
        model.settingsPaperDraft.basisWeightUnit = .gsm
        model.settingsPaperDraft.thicknessValue = "18.9"
        model.settingsPaperDraft.thicknessUnit = .mil
        model.settingsPaperDraft.surfaceTexture = "Smooth"
        model.settingsPaperDraft.baseMaterial = "Cotton"
        model.settingsPaperDraft.mediaColor = "White"
        model.settingsPaperDraft.opacity = "99"
        model.settingsPaperDraft.whiteness = "91"
        model.settingsPaperDraft.obaContent = "None"
        model.settingsPaperDraft.inkCompatibility = "Pigment and dye"
        model.settingsPaperDraft.notes = "Test paper."

        await model.saveSettingsPaper()

        #expect(fakeEngine.lastCreatedPaperInput?.manufacturer == "Hahnemuhle")
        #expect(fakeEngine.lastCreatedPaperInput?.paperLine == "Photo Rag")
        #expect(fakeEngine.lastCreatedPaperInput?.basisWeightValue == "308")
        #expect(fakeEngine.lastCreatedPaperInput?.basisWeightUnit == .gsm)
        #expect(fakeEngine.lastCreatedPaperInput?.thicknessValue == "18.9")
        #expect(fakeEngine.lastCreatedPaperInput?.thicknessUnit == .mil)
        #expect(fakeEngine.lastCreatedPaperInput?.obaContent == "None")
        #expect(fakeEngine.lastCreatedPaperInput?.inkCompatibility == "Pigment and dye")
    }

    @Test
    func publishProfileRefreshesLibrarySelection() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let printer = makePrinter()
        let paper = makePaper()
        let review = ReviewSummaryRecord(
            result: "Pass",
            verifiedAgainstFile: "/tmp/job-1/profile.icc",
            printSettings: "Premium Luster / 1440 dpi",
            lastVerificationDate: "2026-04-19T18:50:00Z",
            averageDe00: 1.2,
            maximumDe00: 2.8,
            notes: "Good first build."
        )
        let reviewDetail = makeJobDetail(
            stage: .review,
            nextAction: "Publish",
            printer: printer,
            paper: paper,
            review: review
        )
        let publishedDetail = makeJobDetail(
            stage: .completed,
            nextAction: "Open in Printer Profiles",
            printer: printer,
            paper: paper,
            review: review,
            publishedProfileId: "profile-1"
        )
        let publishedProfile = makePrinterProfile()

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.appHealthValue = AppHealth(readiness: "ready", blockingIssues: [], warnings: [])
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: reviewDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = reviewDetail
        fakeEngine.publishNewProfileResult = publishedDetail
        fakeEngine.printerProfilesCurrent = []
        fakeEngine.printerProfilesAfterPublish = [publishedProfile]

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()
        await model.publishProfile()

        #expect(fakeEngine.lastPublishedJobId == reviewDetail.id)
        #expect(model.activeNewProfileDetail?.publishedProfileId == "profile-1")
        #expect(model.printerProfiles.map(\.id) == ["profile-1"])
        #expect(model.selectedPrinterProfileID == "profile-1")
    }

    @Test
    func confirmPrinterProfileDeletionReopensSourceJobForReview() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let printer = makePrinter()
        let paper = makePaper()
        let review = ReviewSummaryRecord(
            result: "Pass",
            verifiedAgainstFile: "/tmp/job-1/profile.icc",
            printSettings: "Premium Luster / 1440 dpi",
            lastVerificationDate: "2026-04-19T18:50:00Z",
            averageDe00: 1.2,
            maximumDe00: 2.8,
            notes: "Good first build."
        )
        let publishedDetail = makeJobDetail(
            stage: .completed,
            nextAction: "Open in Printer Profiles",
            printer: printer,
            paper: paper,
            review: review,
            publishedProfileId: "profile-1"
        )
        let reopenedDetail = makeJobDetail(
            stage: .review,
            nextAction: "Publish",
            printer: printer,
            paper: paper,
            review: review
        )
        let publishedProfile = makePrinterProfile()

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.appHealthValue = AppHealth(readiness: "ready", blockingIssues: [], warnings: [])
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.printerProfilesCurrent = [publishedProfile]
        fakeEngine.createNewProfileDraftResult = publishedDetail
        fakeEngine.loadedJobDetails[publishedDetail.id] = publishedDetail
        fakeEngine.deletePrinterProfileResult = DeleteResult(success: true, message: "")
        fakeEngine.jobDetailAfterDeletePrinterProfile = reopenedDetail
        fakeEngine.dashboardSnapshotAfterDeletePrinterProfile = makeDashboard(
            activeWorkItems: [
                makeActiveWorkItem(
                    id: reopenedDetail.id,
                    title: reopenedDetail.title,
                    nextAction: reopenedDetail.nextAction,
                    stage: reopenedDetail.stage
                )
            ]
        )

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()
        model.requestCurrentWorkflowDeletion()
        await model.confirmPendingDeletion()

        #expect(fakeEngine.lastDeletedProfileId == "profile-1")
        #expect(model.activeNewProfileDetail?.stage == .review)
        #expect(model.activeNewProfileDetail?.publishedProfileId == nil)
        #expect(model.printerProfiles.isEmpty)
        #expect(model.activeWorkItems.map(\.id) == [reopenedDetail.id])
        #expect(model.deletionErrorMessage == nil)
    }

    @Test
    func applyToolchainPathPassesTrimmedOverride() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .notFound, path: nil)
        fakeEngine.setToolchainPathResult = makeToolchainStatus(state: .partial, path: "/Applications/ArgyllCMS/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])
        fakeEngine.appHealthValue = AppHealth(
            readiness: "attention",
            blockingIssues: ["ArgyllCMS is missing required tools: targen."],
            warnings: []
        )

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        model.toolchainPathInput = "   /Applications/ArgyllCMS/bin   "
        await model.applyToolchainPath()

        #expect(fakeEngine.lastSetToolchainPath == "/Applications/ArgyllCMS/bin")
        #expect(model.toolchainStatus?.state == .partial)
        #expect(model.toolchainStatus?.resolvedInstallPath == "/Applications/ArgyllCMS/bin")
        #expect(model.bootstrapStatus == nil)
    }
}

private final class FakeEngine: EngineProtocol, @unchecked Sendable {
    private(set) var bootstrapCallCount = 0
    private(set) var createDraftCallCount = 0
    private(set) var lastSetToolchainPath: String?
    private(set) var lastCreateDraftInput: CreateNewProfileDraftInput?
    private(set) var lastCreatedPaperInput: CreatePaperInput?
    private(set) var lastUpdatedPaperInput: UpdatePaperInput?
    private(set) var lastCreatedPresetInput: CreatePrinterPaperPresetInput?
    private(set) var lastSaveContextInput: SaveNewProfileContextInput?
    private(set) var lastPublishedJobId: String?
    private(set) var lastDeletedJobId: String?
    private(set) var lastDeletedProfileId: String?
    private(set) var lastUpdatedPresetInput: UpdatePrinterPaperPresetInput?

    var bootstrapStatusValue = BootstrapStatus(
        appSupportDirReady: true,
        databaseInitialized: true,
        migrationsApplied: true,
        toolchainStatus: makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
    )
    var toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
    var setToolchainPathResult = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
    var dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])
    var appHealthValue = AppHealth(readiness: "ready", blockingIssues: [], warnings: [])
    var logsValue: [LogEntry] = []
    var printersCurrent: [PrinterRecord] = []
    var papersCurrent: [PaperRecord] = []
    var printerPaperPresetsCurrent: [PrinterPaperPresetRecord] = []
    var printerProfilesCurrent: [PrinterProfileRecord] = []
    var printerProfilesAfterPublish: [PrinterProfileRecord]?
    var createNewProfileDraftResult = makeJobDetail(stage: .context, nextAction: "Save Context")
    var saveNewProfileContextResult = makeJobDetail(stage: .target, nextAction: "Generate Target")
    var saveTargetSettingsResult = makeJobDetail(stage: .target, nextAction: "Generate Target")
    var savePrintSettingsResult = makeJobDetail(stage: .print, nextAction: "Mark Chart as Printed")
    var markPrintedResult = makeJobDetail(stage: .drying, nextAction: "Mark Ready to Measure")
    var markReadyResult = makeJobDetail(stage: .measure, nextAction: "Measure")
    var startMeasurementResult = makeJobDetail(stage: .build, nextAction: "Build Profile")
    var startBuildResult = makeJobDetail(stage: .review, nextAction: "Publish")
    var publishNewProfileResult = makeJobDetail(stage: .completed, nextAction: "Open in Printer Profiles", publishedProfileId: "profile-1")
    var deleteNewProfileJobResult = DeleteResult(success: true, message: "")
    var deletePrinterProfileResult = DeleteResult(success: true, message: "")
    var dashboardSnapshotAfterDeletePrinterProfile: DashboardSnapshot?
    var jobDetailAfterDeletePrinterProfile: NewProfileJobDetail?
    var loadedJobDetails: [String: NewProfileJobDetail] = [:]

    func bootstrap(config: EngineConfig) -> BootstrapStatus {
        bootstrapCallCount += 1
        return bootstrapStatusValue
    }

    func createNewProfileDraft(input: CreateNewProfileDraftInput) -> NewProfileJobDetail {
        createDraftCallCount += 1
        lastCreateDraftInput = input
        loadedJobDetails[createNewProfileDraftResult.id] = createNewProfileDraftResult
        return createNewProfileDraftResult
    }

    func deleteNewProfileJob(jobId: String) -> DeleteResult {
        lastDeletedJobId = jobId
        if deleteNewProfileJobResult.success {
            loadedJobDetails.removeValue(forKey: jobId)
            dashboardSnapshotCurrent = makeDashboard(
                activeWorkItems: dashboardSnapshotCurrent.activeWorkItems.filter { $0.id != jobId }
            )
        }
        return deleteNewProfileJobResult
    }

    func deletePrinterProfile(profileId: String) -> DeleteResult {
        lastDeletedProfileId = profileId
        if deletePrinterProfileResult.success {
            let deletedProfile = printerProfilesCurrent.first { $0.id == profileId }
            printerProfilesCurrent.removeAll { $0.id == profileId }
            if let dashboardSnapshotAfterDeletePrinterProfile {
                dashboardSnapshotCurrent = dashboardSnapshotAfterDeletePrinterProfile
            }
            if let sourceJobId = deletedProfile?.createdFromJobId,
               let jobDetailAfterDeletePrinterProfile
            {
                loadedJobDetails[sourceJobId] = jobDetailAfterDeletePrinterProfile
            }
        }
        return deletePrinterProfileResult
    }

    func createPaper(input: CreatePaperInput) -> PaperRecord {
        lastCreatedPaperInput = input
        let record = PaperRecord(
            id: UUID().uuidString,
            manufacturer: input.manufacturer,
            paperLine: input.paperLine,
            surfaceClass: input.surfaceClass,
            basisWeightValue: input.basisWeightValue,
            basisWeightUnit: input.basisWeightUnit,
            thicknessValue: input.thicknessValue,
            thicknessUnit: input.thicknessUnit,
            surfaceTexture: input.surfaceTexture,
            baseMaterial: input.baseMaterial,
            mediaColor: input.mediaColor,
            opacity: input.opacity,
            whiteness: input.whiteness,
            obaContent: input.obaContent,
            inkCompatibility: input.inkCompatibility,
            notes: input.notes,
            displayName: makePaperDisplayName(manufacturer: input.manufacturer, paperLine: input.paperLine),
            createdAt: "2026-04-19T18:30:00Z",
            updatedAt: "2026-04-19T18:30:00Z"
        )
        papersCurrent.append(record)
        return record
    }

    func createPrinter(input: CreatePrinterInput) -> PrinterRecord {
        let record = PrinterRecord(
            id: UUID().uuidString,
            manufacturer: input.manufacturer,
            model: input.model,
            nickname: input.nickname,
            transportStyle: input.transportStyle,
            colorantFamily: input.colorantFamily,
            channelCount: input.channelCount,
            channelLabels: input.channelLabels,
            supportedMediaSettings: input.supportedMediaSettings,
            supportedQualityModes: input.supportedQualityModes,
            monochromePathNotes: input.monochromePathNotes,
            notes: input.notes,
            displayName: makePrinterDisplayName(
                manufacturer: input.manufacturer,
                model: input.model,
                nickname: input.nickname
            ),
            createdAt: "2026-04-19T18:30:00Z",
            updatedAt: "2026-04-19T18:30:00Z"
        )
        printersCurrent.append(record)
        return record
    }

    func createPrinterPaperPreset(input: CreatePrinterPaperPresetInput) -> PrinterPaperPresetRecord {
        lastCreatedPresetInput = input
        let record = PrinterPaperPresetRecord(
            id: UUID().uuidString,
            printerId: input.printerId,
            paperId: input.paperId,
            label: input.label,
            printPath: input.printPath,
            mediaSetting: input.mediaSetting,
            qualityMode: input.qualityMode,
            totalInkLimitPercent: input.totalInkLimitPercent,
            blackInkLimitPercent: input.blackInkLimitPercent,
            notes: input.notes,
            displayName: makePresetDisplayName(
                label: input.label,
                printPath: input.printPath,
                mediaSetting: input.mediaSetting,
                qualityMode: input.qualityMode
            ),
            createdAt: "2026-04-19T18:30:00Z",
            updatedAt: "2026-04-19T18:30:00Z"
        )
        printerPaperPresetsCurrent.append(record)
        return record
    }

    func getAppHealth() -> AppHealth {
        appHealthValue
    }

    func getDashboardSnapshot() -> DashboardSnapshot {
        dashboardSnapshotCurrent
    }

    func getNewProfileJobDetail(jobId: String) -> NewProfileJobDetail {
        loadedJobDetails[jobId] ?? createNewProfileDraftResult
    }

    func getRecentLogs(limit: UInt32) -> [LogEntry] {
        Array(logsValue.prefix(Int(limit)))
    }

    func getToolchainStatus() -> ToolchainStatus {
        toolchainStatusValue
    }

    func listPapers() -> [PaperRecord] {
        papersCurrent
    }

    func listPrinterPaperPresets() -> [PrinterPaperPresetRecord] {
        printerPaperPresetsCurrent
    }

    func listPrinterProfiles() -> [PrinterProfileRecord] {
        printerProfilesCurrent
    }

    func listPrinters() -> [PrinterRecord] {
        printersCurrent
    }

    func markNewProfilePrinted(jobId: String) -> NewProfileJobDetail {
        loadedJobDetails[jobId] = markPrintedResult
        return markPrintedResult
    }

    func markNewProfileReadyToMeasure(jobId: String) -> NewProfileJobDetail {
        loadedJobDetails[jobId] = markReadyResult
        return markReadyResult
    }

    func publishNewProfile(jobId: String) -> NewProfileJobDetail {
        lastPublishedJobId = jobId
        loadedJobDetails[jobId] = publishNewProfileResult
        if let printerProfilesAfterPublish {
            printerProfilesCurrent = printerProfilesAfterPublish
        }
        return publishNewProfileResult
    }

    func saveNewProfileContext(input: SaveNewProfileContextInput) -> NewProfileJobDetail {
        lastSaveContextInput = input
        loadedJobDetails[input.jobId] = saveNewProfileContextResult
        return saveNewProfileContextResult
    }

    func savePrintSettings(input: SavePrintSettingsInput) -> NewProfileJobDetail {
        loadedJobDetails[input.jobId] = savePrintSettingsResult
        return savePrintSettingsResult
    }

    func saveTargetSettings(input: SaveTargetSettingsInput) -> NewProfileJobDetail {
        loadedJobDetails[input.jobId] = saveTargetSettingsResult
        return saveTargetSettingsResult
    }

    func setToolchainPath(path: String?) -> ToolchainStatus {
        lastSetToolchainPath = path
        toolchainStatusValue = setToolchainPathResult
        return setToolchainPathResult
    }

    func startBuildProfile(jobId: String) -> NewProfileJobDetail {
        loadedJobDetails[jobId] = startBuildResult
        return startBuildResult
    }

    func startGenerateTarget(jobId: String) -> NewProfileJobDetail {
        loadedJobDetails[jobId] = savePrintSettingsResult
        return savePrintSettingsResult
    }

    func startMeasurement(input: StartMeasurementInput) -> NewProfileJobDetail {
        loadedJobDetails[input.jobId] = startMeasurementResult
        return startMeasurementResult
    }

    func updatePaper(input: UpdatePaperInput) -> PaperRecord {
        lastUpdatedPaperInput = input
        let record = PaperRecord(
            id: input.id,
            manufacturer: input.manufacturer,
            paperLine: input.paperLine,
            surfaceClass: input.surfaceClass,
            basisWeightValue: input.basisWeightValue,
            basisWeightUnit: input.basisWeightUnit,
            thicknessValue: input.thicknessValue,
            thicknessUnit: input.thicknessUnit,
            surfaceTexture: input.surfaceTexture,
            baseMaterial: input.baseMaterial,
            mediaColor: input.mediaColor,
            opacity: input.opacity,
            whiteness: input.whiteness,
            obaContent: input.obaContent,
            inkCompatibility: input.inkCompatibility,
            notes: input.notes,
            displayName: makePaperDisplayName(manufacturer: input.manufacturer, paperLine: input.paperLine),
            createdAt: "2026-04-19T18:30:00Z",
            updatedAt: "2026-04-19T18:35:00Z"
        )
        papersCurrent.removeAll { $0.id == input.id }
        papersCurrent.append(record)
        return record
    }

    func updatePrinter(input: UpdatePrinterInput) -> PrinterRecord {
        let record = PrinterRecord(
            id: input.id,
            manufacturer: input.manufacturer,
            model: input.model,
            nickname: input.nickname,
            transportStyle: input.transportStyle,
            colorantFamily: input.colorantFamily,
            channelCount: input.channelCount,
            channelLabels: input.channelLabels,
            supportedMediaSettings: input.supportedMediaSettings,
            supportedQualityModes: input.supportedQualityModes,
            monochromePathNotes: input.monochromePathNotes,
            notes: input.notes,
            displayName: makePrinterDisplayName(
                manufacturer: input.manufacturer,
                model: input.model,
                nickname: input.nickname
            ),
            createdAt: "2026-04-19T18:30:00Z",
            updatedAt: "2026-04-19T18:35:00Z"
        )
        printersCurrent.removeAll { $0.id == input.id }
        printersCurrent.append(record)
        return record
    }

    func updatePrinterPaperPreset(input: UpdatePrinterPaperPresetInput) -> PrinterPaperPresetRecord {
        lastUpdatedPresetInput = input
        let record = PrinterPaperPresetRecord(
            id: input.id,
            printerId: input.printerId,
            paperId: input.paperId,
            label: input.label,
            printPath: input.printPath,
            mediaSetting: input.mediaSetting,
            qualityMode: input.qualityMode,
            totalInkLimitPercent: input.totalInkLimitPercent,
            blackInkLimitPercent: input.blackInkLimitPercent,
            notes: input.notes,
            displayName: makePresetDisplayName(
                label: input.label,
                printPath: input.printPath,
                mediaSetting: input.mediaSetting,
                qualityMode: input.qualityMode
            ),
            createdAt: "2026-04-19T18:30:00Z",
            updatedAt: "2026-04-19T18:35:00Z"
        )
        printerPaperPresetsCurrent.removeAll { $0.id == input.id }
        printerPaperPresetsCurrent.append(record)
        return record
    }
}

private func makeToolchainStatus(state: ToolchainState, path: String?) -> ToolchainStatus {
    ToolchainStatus(
        state: state,
        resolvedInstallPath: path,
        discoveredExecutables: path == nil ? [] : ["targen", "printtarg", "chartread", "scanin", "colprof", "profcheck"],
        missingExecutables: path == nil ? ["targen"] : [],
        argyllVersion: path == nil ? nil : "3.5.0",
        lastValidationTime: "2026-04-19T18:30:00Z"
    )
}

private func makeDashboard(activeWorkItems: [ActiveWorkItem]) -> DashboardSnapshot {
    DashboardSnapshot(
        activeWorkItems: activeWorkItems,
        jobsCount: UInt32(activeWorkItems.count),
        alertsCount: 0,
        instrumentStatus: InstrumentStatus(
            state: .disconnected,
            label: "No Instrument Connected",
            detail: nil
        )
    )
}

private func makeActiveWorkItem(
    id: String,
    title: String = "P900 Rag v1",
    nextAction: String = "Save Context",
    stage: WorkflowStage = .context,
    printerName: String = "Studio P900",
    paperName: String = "Canson Rag"
) -> ActiveWorkItem {
    ActiveWorkItem(
        id: id,
        title: title,
        nextAction: nextAction,
        kind: "new_profile",
        stage: stage,
        profileName: title,
        printerName: printerName,
        paperName: paperName,
        status: "context"
    )
}

private func makePrinter() -> PrinterRecord {
    PrinterRecord(
        id: "printer-1",
        manufacturer: "Epson",
        model: "SureColor P900",
        nickname: "Studio P900",
        transportStyle: "Rear tray",
        colorantFamily: .cmyk,
        channelCount: 4,
        channelLabels: [],
        supportedMediaSettings: ["Premium Luster", "Ultra Premium Presentation Matte"],
        supportedQualityModes: ["1440 dpi", "2880 dpi"],
        monochromePathNotes: "Use the neutral path for black-and-white work.",
        notes: "Main studio printer.",
        displayName: "Studio P900 (Epson SureColor P900)",
        createdAt: "2026-04-19T18:30:00Z",
        updatedAt: "2026-04-19T18:30:00Z"
    )
}

private func makeAlternatePrinter() -> PrinterRecord {
    PrinterRecord(
        id: "printer-2",
        manufacturer: "Canon",
        model: "imagePROGRAF PRO-1000",
        nickname: "Studio PRO-1000",
        transportStyle: "Manual feed",
        colorantFamily: .rgb,
        channelCount: 3,
        channelLabels: [],
        supportedMediaSettings: ["Fine Art Smooth"],
        supportedQualityModes: ["High"],
        monochromePathNotes: "",
        notes: "Alternate print path.",
        displayName: "Studio PRO-1000 (Canon imagePROGRAF PRO-1000)",
        createdAt: "2026-04-19T18:30:00Z",
        updatedAt: "2026-04-19T18:30:00Z"
    )
}

private func makePaper() -> PaperRecord {
    PaperRecord(
        id: "paper-1",
        manufacturer: "Canson",
        paperLine: "Rag Photographique",
        surfaceClass: "Matte",
        basisWeightValue: "310",
        basisWeightUnit: .gsm,
        thicknessValue: "15.7",
        thicknessUnit: .mil,
        surfaceTexture: "Smooth",
        baseMaterial: "Cotton rag",
        mediaColor: "White",
        opacity: "98",
        whiteness: "89",
        obaContent: "Low OBA",
        inkCompatibility: "Pigment",
        notes: "Preferred for gallery proofs.",
        displayName: "Canson Rag Photographique",
        createdAt: "2026-04-19T18:30:00Z",
        updatedAt: "2026-04-19T18:30:00Z"
    )
}

private func makeAlternatePaper() -> PaperRecord {
    PaperRecord(
        id: "paper-2",
        manufacturer: "Hahnemuhle",
        paperLine: "Photo Rag",
        surfaceClass: "Matte",
        basisWeightValue: "308",
        basisWeightUnit: .gsm,
        thicknessValue: "18.9",
        thicknessUnit: .mil,
        surfaceTexture: "Smooth",
        baseMaterial: "Cotton",
        mediaColor: "White",
        opacity: "99",
        whiteness: "91",
        obaContent: "None",
        inkCompatibility: "Pigment",
        notes: "Alternate paper path.",
        displayName: "Hahnemuhle Photo Rag",
        createdAt: "2026-04-19T18:30:00Z",
        updatedAt: "2026-04-19T18:30:00Z"
    )
}

private func makePreset(
    id: String = "preset-1",
    printerId: String = "printer-1",
    paperId: String = "paper-1"
) -> PrinterPaperPresetRecord {
    PrinterPaperPresetRecord(
        id: id,
        printerId: printerId,
        paperId: paperId,
        label: "Studio Matte",
        printPath: "Mirage",
        mediaSetting: "Premium Luster",
        qualityMode: "1440 dpi",
        totalInkLimitPercent: 280,
        blackInkLimitPercent: 90,
        notes: "Matches the standard studio print path.",
        displayName: "Studio Matte",
        createdAt: "2026-04-19T18:30:00Z",
        updatedAt: "2026-04-19T18:30:00Z"
    )
}

private func makePrinterProfile() -> PrinterProfileRecord {
    PrinterProfileRecord(
        id: "profile-1",
        name: "P900 Rag v1",
        printerName: "Studio P900",
        paperName: "Canson Rag Photographique",
        contextStatus: "Published",
        profilePath: "/tmp/job-1/profile.icc",
        measurementPath: "/tmp/job-1/measurements.ti3",
        printSettings: "Premium Luster / 1440 dpi",
        verifiedAgainstFile: "/tmp/job-1/profile.icc",
        result: "Pass",
        lastVerificationDate: "2026-04-19T18:50:00Z",
        createdFromJobId: "job-1",
        createdAt: "2026-04-19T18:50:00Z",
        updatedAt: "2026-04-19T18:50:00Z"
    )
}

private func makeJobDetail(
    id: String = "job-1",
    title: String = "P900 Rag v1",
    stage: WorkflowStage,
    nextAction: String,
    printer: PrinterRecord? = nil,
    paper: PaperRecord? = nil,
    preset: PrinterPaperPresetRecord? = nil,
    printPath: String = "",
    review: ReviewSummaryRecord? = nil,
    publishedProfileId: String? = nil
) -> NewProfileJobDetail {
    NewProfileJobDetail(
        id: id,
        title: title,
        status: stage == .completed ? "completed" : "active",
        stage: stage,
        nextAction: nextAction,
        profileName: title,
        printerName: printer?.displayName ?? "Studio P900",
        paperName: paper?.displayName ?? "Canson Rag Photographique",
        workspacePath: "/tmp/\(id)",
        printer: printer,
        paper: paper,
        context: NewProfileContextRecord(
            printerPaperPresetId: preset?.id,
            printPath: preset?.printPath ?? printPath,
            mediaSetting: preset?.mediaSetting ?? "Premium Luster",
            qualityMode: preset?.qualityMode ?? "1440 dpi",
            colorantFamily: printer?.colorantFamily ?? .cmyk,
            channelCount: printer?.channelCount ?? 4,
            channelLabels: printer?.channelLabels ?? [],
            totalInkLimitPercent: preset?.totalInkLimitPercent,
            blackInkLimitPercent: preset?.blackInkLimitPercent,
            printPathNotes: "Rear tray",
            measurementNotes: "Warm up the instrument.",
            measurementObserver: "2",
            measurementIlluminant: "D50",
            measurementMode: .strip
        ),
        targetSettings: TargetSettingsRecord(
            patchCount: 928,
            improveNeutrals: true,
            useExistingProfileToHelpTargetPlanning: false,
            planningProfileId: nil,
            planningProfileName: nil
        ),
        printSettings: PrintSettingsRecord(
            printWithoutColorManagement: true,
            dryingTimeMinutes: 30,
            printedAt: "2026-04-19T18:30:00Z",
            dryingReadyAt: "2026-04-19T19:00:00Z"
        ),
        measurement: MeasurementStatusRecord(
            measurementSourcePath: stage == .build || stage == .review || stage == .completed ? "/tmp/\(id)/measurements.ti3" : nil,
            scanFilePath: nil,
            hasMeasurementCheckpoint: false
        ),
        latestError: nil,
        publishedProfileId: publishedProfileId,
        review: review,
        stageTimeline: [
            WorkflowStageSummary(stage: .context, title: "Context", state: stage == .context ? .current : .completed),
            WorkflowStageSummary(stage: .target, title: "Target", state: stage == .target ? .current : .upcoming),
            WorkflowStageSummary(stage: .print, title: "Print", state: stage == .print ? .current : .upcoming),
            WorkflowStageSummary(stage: .measure, title: "Measure", state: stage == .measure ? .current : .upcoming),
            WorkflowStageSummary(stage: .review, title: "Review", state: stage == .review ? .current : .upcoming)
        ],
        artifacts: [],
        commands: [],
        isCommandRunning: false
    )
}

private func makePrinterDisplayName(manufacturer: String, model: String, nickname: String) -> String {
    let makeModel = [manufacturer, model]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    return nickname.isEmpty ? makeModel : "\(nickname) (\(makeModel))"
}

private func makePaperDisplayName(manufacturer: String, paperLine: String) -> String {
    [manufacturer, paperLine]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func makePresetDisplayName(label: String, printPath: String, mediaSetting: String, qualityMode: String) -> String {
    guard label.isEmpty else { return label }

    let parts = [printPath, mediaSetting, qualityMode]
        .filter { !$0.isEmpty }

    return parts.joined(separator: " / ")
}
