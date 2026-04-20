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
        fakeEngine.deleteNewProfileJobResult = DeleteJobResult(success: true, message: "")

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()
        await model.openCliTranscript(jobId: draftDetail.id)
        model.requestActiveWorkDeletion(makeActiveWorkItem(id: draftDetail.id))
        await model.confirmActiveWorkDeletion()

        #expect(fakeEngine.lastDeletedJobId == draftDetail.id)
        #expect(model.activeNewProfileDetail == nil)
        #expect(model.activeWorkItems.isEmpty)
        #expect(model.activeWorkDeletionErrorMessage == nil)

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
        await model.confirmActiveWorkDeletion()

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
        fakeEngine.deleteNewProfileJobResult = DeleteJobResult(success: false, message: "Database is locked.")

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()
        model.requestActiveWorkDeletion(makeActiveWorkItem(id: draftDetail.id))
        await model.confirmActiveWorkDeletion()

        #expect(model.activeNewProfileDetail?.id == draftDetail.id)
        #expect(model.activeWorkItems.map(\.id) == [draftDetail.id])
        #expect(model.activeWorkDeletionErrorMessage == "Database is locked.")
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
        let draftDetail = makeJobDetail(stage: .context, nextAction: "Save Context", printer: printer, paper: paper)
        let savedDetail = makeJobDetail(stage: .target, nextAction: "Generate Target", printer: printer, paper: paper)

        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .ready, path: "/opt/homebrew/bin")
        fakeEngine.appHealthValue = AppHealth(readiness: "ready", blockingIssues: [], warnings: [])
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [makeActiveWorkItem(id: draftDetail.id)])
        fakeEngine.printersCurrent = [printer]
        fakeEngine.papersCurrent = [paper]
        fakeEngine.createNewProfileDraftResult = draftDetail
        fakeEngine.saveNewProfileContextResult = savedDetail

        let model = AppModel(storagePaths: .fixture(root: root), engine: fakeEngine)
        await model.openNewProfileWorkflow()

        model.workflowProfileName = "P900 Rag v1"
        model.workflowSelectedPrinterID = printer.id
        model.workflowSelectedPaperID = paper.id
        model.workflowMediaSetting = "Premium Luster"
        model.workflowQualityMode = "1440 dpi"
        model.workflowPrintPathNotes = "Rear tray"
        model.workflowMeasurementNotes = "Warm up the instrument."
        model.workflowMeasurementObserver = "2"
        model.workflowMeasurementIlluminant = "D50"
        model.workflowMeasurementMode = .patch

        await model.saveWorkflowContext()

        #expect(fakeEngine.lastSaveContextInput?.jobId == draftDetail.id)
        #expect(fakeEngine.lastSaveContextInput?.printerId == printer.id)
        #expect(fakeEngine.lastSaveContextInput?.paperId == paper.id)
        #expect(fakeEngine.lastSaveContextInput?.measurementMode == .patch)
        #expect(model.activeNewProfileDetail?.stage == .target)
        #expect(model.workflowPatchCount == "928")
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
    private(set) var lastSaveContextInput: SaveNewProfileContextInput?
    private(set) var lastPublishedJobId: String?
    private(set) var lastDeletedJobId: String?

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
    var deleteNewProfileJobResult = DeleteJobResult(success: true, message: "")
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

    func deleteNewProfileJob(jobId: String) -> DeleteJobResult {
        lastDeletedJobId = jobId
        if deleteNewProfileJobResult.success {
            loadedJobDetails.removeValue(forKey: jobId)
            dashboardSnapshotCurrent = makeDashboard(
                activeWorkItems: dashboardSnapshotCurrent.activeWorkItems.filter { $0.id != jobId }
            )
        }
        return deleteNewProfileJobResult
    }

    func createPaper(input: CreatePaperInput) -> PaperRecord {
        let record = PaperRecord(
            id: UUID().uuidString,
            vendorProductName: input.vendorProductName,
            surfaceClass: input.surfaceClass,
            weightThickness: input.weightThickness,
            obaFluorescenceNotes: input.obaFluorescenceNotes,
            notes: input.notes,
            displayName: input.vendorProductName,
            createdAt: "2026-04-19T18:30:00Z",
            updatedAt: "2026-04-19T18:30:00Z"
        )
        papersCurrent.append(record)
        return record
    }

    func createPrinter(input: CreatePrinterInput) -> PrinterRecord {
        let record = PrinterRecord(
            id: UUID().uuidString,
            makeModel: input.makeModel,
            nickname: input.nickname,
            transportStyle: input.transportStyle,
            supportedQualityModes: input.supportedQualityModes,
            monochromePathNotes: input.monochromePathNotes,
            notes: input.notes,
            displayName: input.nickname.isEmpty ? input.makeModel : "\(input.nickname) (\(input.makeModel))",
            createdAt: "2026-04-19T18:30:00Z",
            updatedAt: "2026-04-19T18:30:00Z"
        )
        printersCurrent.append(record)
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
        let record = PaperRecord(
            id: input.id,
            vendorProductName: input.vendorProductName,
            surfaceClass: input.surfaceClass,
            weightThickness: input.weightThickness,
            obaFluorescenceNotes: input.obaFluorescenceNotes,
            notes: input.notes,
            displayName: input.vendorProductName,
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
            makeModel: input.makeModel,
            nickname: input.nickname,
            transportStyle: input.transportStyle,
            supportedQualityModes: input.supportedQualityModes,
            monochromePathNotes: input.monochromePathNotes,
            notes: input.notes,
            displayName: input.nickname.isEmpty ? input.makeModel : "\(input.nickname) (\(input.makeModel))",
            createdAt: "2026-04-19T18:30:00Z",
            updatedAt: "2026-04-19T18:35:00Z"
        )
        printersCurrent.removeAll { $0.id == input.id }
        printersCurrent.append(record)
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
        makeModel: "Epson SureColor P900",
        nickname: "Studio P900",
        transportStyle: "Rear tray",
        supportedQualityModes: ["1440 dpi", "2880 dpi"],
        monochromePathNotes: "Use the neutral path for black-and-white work.",
        notes: "Main studio printer.",
        displayName: "Studio P900 (Epson SureColor P900)",
        createdAt: "2026-04-19T18:30:00Z",
        updatedAt: "2026-04-19T18:30:00Z"
    )
}

private func makePaper() -> PaperRecord {
    PaperRecord(
        id: "paper-1",
        vendorProductName: "Canson Rag Photographique",
        surfaceClass: "Matte",
        weightThickness: "310 gsm",
        obaFluorescenceNotes: "Low OBA",
        notes: "Preferred for gallery proofs.",
        displayName: "Canson Rag Photographique",
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
            mediaSetting: "Premium Luster",
            qualityMode: "1440 dpi",
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
