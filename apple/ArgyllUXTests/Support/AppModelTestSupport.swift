import Foundation
import Testing
@testable import ArgyllUX

struct TestFileOpener: FileOpening {
    func revealPathInFinder(_ path: String) {}
    func openPath(_ path: String) {}
}

func makeTemporaryRoot() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
}

@MainActor
func makeAppModel(root: URL? = nil, fakeEngine: FakeEngine = FakeEngine()) -> AppModel {
    AppModel(
        storagePaths: .fixture(root: root ?? makeTemporaryRoot()),
        engine: fakeEngine,
        fileOpener: TestFileOpener()
    )
}

@MainActor
func makeSettingsModel(fakeEngine: FakeEngine = FakeEngine()) -> SettingsCatalogModel {
    SettingsCatalogModel(bridge: EngineBridge(engine: fakeEngine))
}

@MainActor
func makeWorkflowModel(fakeEngine: FakeEngine = FakeEngine()) -> NewProfileWorkflowModel {
    NewProfileWorkflowModel(
        bridge: EngineBridge(engine: fakeEngine),
        fileOpener: TestFileOpener()
    )
}

@MainActor
func makeCliTranscriptModel(fakeEngine: FakeEngine = FakeEngine()) -> CliTranscriptModel {
    CliTranscriptModel(
        bridge: EngineBridge(engine: fakeEngine),
        fileOpener: TestFileOpener()
    )
}

func makeReferenceData(
    printers: [PrinterRecord] = [],
    papers: [PaperRecord] = [],
    printerPaperPresets: [PrinterPaperPresetRecord] = [],
    printerProfiles: [PrinterProfileRecord] = []
) -> AppReferenceData {
    AppReferenceData(
        printers: printers,
        papers: papers,
        printerPaperPresets: printerPaperPresets,
        printerProfiles: printerProfiles
    )
}

final class FakeEngine: EngineProtocol, @unchecked Sendable {
    private(set) var bootstrapCallCount = 0
    private(set) var createDraftCallCount = 0
    private(set) var resolveNewProfileLaunchCallCount = 0
    private(set) var lastSetToolchainPath: String?
    private(set) var lastCreateDraftInput: CreateNewProfileDraftInput?
    private(set) var lastResolveNewProfileLaunchInput: CreateNewProfileDraftInput?
    private(set) var lastCreatedPaperInput: CreatePaperInput?
    private(set) var lastUpdatedPaperInput: UpdatePaperInput?
    private(set) var lastCreatedPresetInput: CreatePrinterPaperPresetInput?
    private(set) var lastSaveContextInput: SaveNewProfileContextInput?
    private(set) var lastPublishedJobId: String?
    private(set) var lastDeletedJobId: String?
    private(set) var lastDeletedProfileId: String?
    private(set) var lastUpdatedPresetInput: UpdatePrinterPaperPresetInput?
    private(set) var recordedDiagnosticInputs: [DiagnosticEventInput] = []
    private(set) var lastDiagnosticFilter: DiagnosticEventFilter?

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
    var printersCurrent: [PrinterRecord] = []
    var papersCurrent: [PaperRecord] = []
    var printerPaperPresetsCurrent: [PrinterPaperPresetRecord] = []
    var printerProfilesCurrent: [PrinterProfileRecord] = []
    var printerProfilesAfterPublish: [PrinterProfileRecord]?
    var createNewProfileDraftResult = makeJobDetail(stage: .context, nextAction: "Save Context")
    var resolveNewProfileLaunchResult: NewProfileJobDetail?
    var saveNewProfileContextResult = makeJobDetail(stage: .target, nextAction: "Generate Target")
    var saveTargetSettingsResult = makeJobDetail(stage: .target, nextAction: "Generate Target")
    var savePrintSettingsResult = makeJobDetail(stage: .print, nextAction: "Mark Chart as Printed")
    var markPrintedResult = makeJobDetail(stage: .drying, nextAction: "Mark Ready to Measure")
    var markReadyResult = makeJobDetail(stage: .measure, nextAction: "Measure")
    var startMeasurementResult = makeJobDetail(stage: .build, nextAction: "Build Profile")
    var startBuildResult = makeJobDetail(stage: .review, nextAction: "Publish")
    var publishNewProfileResult = makeJobDetail(
        stage: .completed,
        nextAction: "Open in Printer Profiles",
        publishedProfileId: "profile-1"
    )
    var deleteNewProfileJobResult = DeleteResult(success: true, message: "")
    var deletePrinterProfileResult = DeleteResult(success: true, message: "")
    var dashboardSnapshotAfterDeletePrinterProfile: DashboardSnapshot?
    var jobDetailAfterDeletePrinterProfile: NewProfileJobDetail?
    var loadedJobDetails: [String: NewProfileJobDetail] = [:]
    var diagnosticEventsValue: [DiagnosticEventRecord] = []
    var diagnosticsSummaryValue = makeDiagnosticsSummary()

    func bootstrap(config: EngineConfig) -> BootstrapStatus {
        bootstrapCallCount += 1
        return bootstrapStatusValue
    }

    func createNewProfileDraft(input: CreateNewProfileDraftInput) -> NewProfileJobDetail {
        createDraft(input: input)
    }

    func resolveNewProfileLaunch(input: CreateNewProfileDraftInput) -> NewProfileJobDetail {
        resolveNewProfileLaunchCallCount += 1
        lastResolveNewProfileLaunchInput = input

        if let resolveNewProfileLaunchResult {
            loadedJobDetails[resolveNewProfileLaunchResult.id] = resolveNewProfileLaunchResult
            upsertActiveWorkItem(for: resolveNewProfileLaunchResult)
            return resolveNewProfileLaunchResult
        }

        if let existingJobId = dashboardSnapshotCurrent.activeWorkItems.first(where: { $0.kind == "new_profile" })?.id {
            let detail = loadedJobDetails[existingJobId] ?? createNewProfileDraftResult
            loadedJobDetails[detail.id] = detail
            upsertActiveWorkItem(for: detail)
            return detail
        }

        return createDraft(input: input)
    }

    private func createDraft(input: CreateNewProfileDraftInput) -> NewProfileJobDetail {
        createDraftCallCount += 1
        lastCreateDraftInput = input
        loadedJobDetails[createNewProfileDraftResult.id] = createNewProfileDraftResult
        upsertActiveWorkItem(for: createNewProfileDraftResult)
        return createNewProfileDraftResult
    }

    private func upsertActiveWorkItem(for detail: NewProfileJobDetail) {
        let item = makeActiveWorkItem(
            id: detail.id,
            title: detail.title,
            nextAction: detail.nextAction,
            stage: detail.stage,
            printerName: detail.printerName,
            paperName: detail.paperName,
            status: detail.status
        )
        dashboardSnapshotCurrent = makeDashboard(
            activeWorkItems: [item] + dashboardSnapshotCurrent.activeWorkItems.filter { $0.id != detail.id }
        )
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

    func recordDiagnosticEvent(input: DiagnosticEventInput) -> DiagnosticEventRecord {
        recordedDiagnosticInputs.append(input)
        let record = makeDiagnosticEvent(
            level: input.level,
            category: input.category,
            message: input.message,
            jobId: input.jobId,
            commandId: input.commandId
        )
        diagnosticEventsValue.insert(record, at: 0)
        return record
    }

    func listDiagnosticEvents(filter: DiagnosticEventFilter) -> [DiagnosticEventRecord] {
        lastDiagnosticFilter = filter
        return diagnosticEventsValue
    }

    func getDiagnosticsSummary() -> DiagnosticsSummary {
        diagnosticsSummaryValue
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
        []
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

func makeToolchainStatus(state: ToolchainState, path: String?) -> ToolchainStatus {
    ToolchainStatus(
        state: state,
        resolvedInstallPath: path,
        discoveredExecutables: path == nil ? [] : ["targen", "printtarg", "chartread", "scanin", "colprof", "profcheck"],
        missingExecutables: path == nil ? ["targen"] : [],
        argyllVersion: path == nil ? nil : "3.5.0",
        lastValidationTime: "2026-04-19T18:30:00Z"
    )
}

func makeDashboard(activeWorkItems: [ActiveWorkItem]) -> DashboardSnapshot {
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

func makeDiagnosticsSummary(
    total: UInt32 = 0,
    warnings: UInt32 = 0,
    errors: UInt32 = 0,
    critical: UInt32 = 0
) -> DiagnosticsSummary {
    DiagnosticsSummary(
        totalCount: total,
        warningCount: warnings,
        errorCount: errors,
        criticalCount: critical,
        latestCriticalMessage: nil,
        latestEventTimestamp: nil,
        appReadiness: "Ready",
        argyllVersion: "3.5.0",
        argyllPathCategory: "system_toolchain",
        retention: DiagnosticsRetentionStatus(
            retainedDays: 30,
            maxStorageMb: 50,
            maxPayloadBytes: 65536,
            eventCount: total,
            estimatedStorageBytes: 2048,
            lastPrunedAt: nil
        )
    )
}

func makeDiagnosticEvent(
    level: DiagnosticLevel = .info,
    category: DiagnosticCategory = .app,
    message: String = "Diagnostic event.",
    jobId: String? = nil,
    commandId: String? = nil
) -> DiagnosticEventRecord {
    DiagnosticEventRecord(
        id: UUID().uuidString,
        timestamp: "2026-04-26T18:30:00Z",
        level: level,
        category: category,
        source: "test.diagnostics",
        message: message,
        detailsJson: "{}",
        privacy: .public,
        jobId: jobId,
        commandId: commandId,
        profileId: nil,
        issueCaseId: nil,
        durationMs: nil,
        operationId: nil,
        parentOperationId: nil
    )
}

func makeActiveWorkItem(
    id: String,
    title: String = "P900 Rag v1",
    nextAction: String = "Save Context",
    stage: WorkflowStage = .context,
    printerName: String = "Studio P900",
    paperName: String = "Canson Rag",
    status: String = "context"
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
        status: status
    )
}

func makePrinter() -> PrinterRecord {
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

func makeAlternatePrinter() -> PrinterRecord {
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

func makePaper() -> PaperRecord {
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

func makeAlternatePaper() -> PaperRecord {
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

func makePreset(
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

func makePrinterProfile() -> PrinterProfileRecord {
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

func makeAlternatePrinterProfile() -> PrinterProfileRecord {
    PrinterProfileRecord(
        id: "profile-2",
        name: "PRO-1000 Rag v2",
        printerName: "Studio PRO-1000",
        paperName: "Hahnemuhle Photo Rag",
        contextStatus: "Published",
        profilePath: "/tmp/job-2/profile.icc",
        measurementPath: "/tmp/job-2/measurements.ti3",
        printSettings: "Fine Art Smooth / High",
        verifiedAgainstFile: "/tmp/job-2/profile.icc",
        result: "Pass",
        lastVerificationDate: "2026-04-19T19:10:00Z",
        createdFromJobId: "job-2",
        createdAt: "2026-04-19T19:10:00Z",
        updatedAt: "2026-04-19T19:10:00Z"
    )
}

func makeJobDetail(
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

func makePrinterDisplayName(manufacturer: String, model: String, nickname: String) -> String {
    let makeModel = [manufacturer, model]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    return nickname.isEmpty ? makeModel : "\(nickname) (\(makeModel))"
}

func makePaperDisplayName(manufacturer: String, paperLine: String) -> String {
    [manufacturer, paperLine]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

func makePresetDisplayName(label: String, printPath: String, mediaSetting: String, qualityMode: String) -> String {
    guard label.isEmpty else { return label }

    let parts = [printPath, mediaSetting, qualityMode]
        .filter { !$0.isEmpty }

    return parts.joined(separator: " / ")
}
