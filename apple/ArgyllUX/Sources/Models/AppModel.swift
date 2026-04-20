import AppKit
import Foundation

enum WorkflowDestination: Equatable {
    case newProfile
}

private struct NewProfileSeed: Equatable {
    let printerId: String?
    let paperId: String?
}

private enum NewProfileOpenTarget: Equatable {
    case resumableOrCreate(seed: NewProfileSeed?)
    case job(id: String)
}

enum CliTranscriptTarget: Equatable {
    case latestResumable(jobId: String?)
    case job(jobId: String)

    var resolvedJobId: String? {
        switch self {
        case let .latestResumable(jobId):
            return jobId
        case let .job(jobId):
            return jobId
        }
    }
}

// Transcript state stays separate from the workflow selection so shell-level
// transcript browsing cannot silently retarget the active job detail.
enum CliTranscriptState {
    case empty
    case loading
    case deleted(jobTitle: String?)
    case loaded(NewProfileJobDetail)

    var detail: NewProfileJobDetail? {
        guard case let .loaded(detail) = self else { return nil }
        return detail
    }
}

struct PrinterDraft: Equatable {
    var id: String?
    var makeModel = ""
    var nickname = ""
    var transportStyle = ""
    var supportedQualityModesText = ""
    var monochromePathNotes = ""
    var notes = ""

    init() {}

    init(record: PrinterRecord) {
        id = record.id
        makeModel = record.makeModel
        nickname = record.nickname
        transportStyle = record.transportStyle
        supportedQualityModesText = record.supportedQualityModes.joined(separator: ", ")
        monochromePathNotes = record.monochromePathNotes
        notes = record.notes
    }

    var supportedQualityModes: [String] {
        supportedQualityModesText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var title: String {
        if let id, !id.isEmpty {
            return "Edit Printer"
        }

        return "New Printer"
    }
}

struct PaperDraft: Equatable {
    var id: String?
    var vendorProductName = ""
    var surfaceClass = ""
    var weightThickness = ""
    var obaFluorescenceNotes = ""
    var notes = ""

    init() {}

    init(record: PaperRecord) {
        id = record.id
        vendorProductName = record.vendorProductName
        surfaceClass = record.surfaceClass
        weightThickness = record.weightThickness
        obaFluorescenceNotes = record.obaFluorescenceNotes
        notes = record.notes
    }

    var title: String {
        if let id, !id.isEmpty {
            return "Edit Paper"
        }

        return "New Paper"
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedRoute: AppRoute = .home
    @Published var activeWorkflow: WorkflowDestination?
    @Published var bootstrapStatus: BootstrapStatus?
    @Published var toolchainStatus: ToolchainStatus?
    @Published var dashboardSnapshot: DashboardSnapshot?
    @Published var appHealth: AppHealth?
    @Published var recentLogs: [LogEntry] = []
    @Published var activeWorkDeletionJobID: String?
    @Published var activeWorkDeletionJobTitle = ""
    @Published var activeWorkDeletionErrorMessage: String?
    @Published var printers: [PrinterRecord] = []
    @Published var papers: [PaperRecord] = []
    @Published var printerProfiles: [PrinterProfileRecord] = []
    @Published var selectedPrinterProfileID: String?
    @Published var toolchainPathInput = ""
    @Published var isRefreshing = false

    @Published var activeNewProfileDetail: NewProfileJobDetail?
    @Published var workflowProfileName = ""
    @Published var workflowSelectedPrinterID: String?
    @Published var workflowSelectedPaperID: String?
    @Published var workflowMediaSetting = ""
    @Published var workflowQualityMode = ""
    @Published var workflowPrintPathNotes = ""
    @Published var workflowMeasurementNotes = ""
    @Published var workflowMeasurementObserver = "2"
    @Published var workflowMeasurementIlluminant = "D50"
    @Published var workflowMeasurementMode: MeasurementMode = .strip
    @Published var workflowPatchCount = "928"
    @Published var workflowImproveNeutrals = false
    @Published var workflowUsePlanningProfile = false
    @Published var workflowPlanningProfileID: String?
    @Published var workflowPrintWithoutColorManagement = true
    @Published var workflowDryingTimeMinutes = "30"
    @Published var workflowScanFilePath = ""
    @Published private(set) var cliTranscriptTarget: CliTranscriptTarget?
    @Published private(set) var cliTranscriptState: CliTranscriptState = .empty
    @Published var showWorkflowPrinterForm = false
    @Published var showWorkflowPaperForm = false
    @Published var workflowPrinterDraft = PrinterDraft()
    @Published var workflowPaperDraft = PaperDraft()
    @Published var settingsPrinterDraft = PrinterDraft()
    @Published var settingsPaperDraft = PaperDraft()

    let launcherActions: [LauncherAction] = [
        LauncherAction(title: "New Profile", detail: "Create a printer and paper profile.", kind: .newProfile),
        LauncherAction(title: "Improve Profile", detail: "Locked into the shell.", kind: .placeholder),
        LauncherAction(title: "Import Profile", detail: "Finished ICC profiles.", kind: .placeholder),
        LauncherAction(title: "Import Measurements", detail: "Raw measurement evidence.", kind: .placeholder),
        LauncherAction(title: "Match a Reference", detail: "Reference matching lives here next.", kind: .placeholder),
        LauncherAction(title: "Verify Output", detail: "Verification surface comes next.", kind: .placeholder),
        LauncherAction(title: "Recalibrate", detail: "Maintenance stays distinct.", kind: .placeholder),
        LauncherAction(title: "Rebuild", detail: "Characterization rebuilds stay explicit.", kind: .placeholder),
        LauncherAction(title: "Spot Measure", detail: "Spot reads will land here.", kind: .placeholder),
        LauncherAction(title: "Compare Measurements", detail: "Comparison tooling comes next.", kind: .placeholder),
        LauncherAction(title: "Troubleshoot", detail: "Symptom-first by default.", kind: .placeholder),
        LauncherAction(title: "B&W Tuning", detail: "Monochrome workflow entry point.", kind: .placeholder)
    ]

    let storagePaths: StoragePaths

    private let bridge: EngineBridge
    private var hasBootstrapped = false
    private var workflowPollTask: Task<Void, Never>?
    private var cliTranscriptPollTask: Task<Void, Never>?
    private var lastWorkflowEditorSeed: String?

    init(storagePaths: StoragePaths = .default(), engine: EngineProtocol = Engine()) {
        self.storagePaths = storagePaths
        self.bridge = EngineBridge(engine: engine)
    }

    var activeWorkItems: [ActiveWorkItem] {
        dashboardSnapshot?.activeWorkItems ?? []
    }

    var jobsCount: Int {
        Int(dashboardSnapshot?.jobsCount ?? 0)
    }

    var alertsCount: Int {
        Int(dashboardSnapshot?.alertsCount ?? 0)
    }

    var instrumentStatusLabel: String {
        dashboardSnapshot?.instrumentStatus.label ?? "No Instrument Connected"
    }

    var instrumentStatusTone: StatusBadgeView.Tone {
        switch dashboardSnapshot?.instrumentStatus.state {
        case .connected:
            .ready
        case .attention:
            .attention
        case .disconnected, .none:
            .blocked
        }
    }

    var argylluxVersionLabel: String {
        let info = Bundle.main.infoDictionary
        let marketingVersion = info?["CFBundleShortVersionString"] as? String
        let buildVersion = info?["CFBundleVersion"] as? String

        switch (marketingVersion, buildVersion) {
        case let (marketingVersion?, buildVersion?) where buildVersion != marketingVersion:
            return "\(marketingVersion) (\(buildVersion))"
        case let (marketingVersion?, _):
            return marketingVersion
        case let (_, buildVersion?):
            return buildVersion
        default:
            return "0.1.0"
        }
    }

    var argyllVersionLabel: String {
        toolchainStatus?.argyllVersion ?? "Unknown"
    }

    var argyllStatusLabel: String {
        switch toolchainStatus?.state {
        case .ready:
            "Ready"
        case .partial:
            "Partially Available"
        case .notFound, .none:
            "Not Found"
        }
    }

    var detectedToolchainPath: String {
        toolchainStatus?.resolvedInstallPath ?? "Not found"
    }

    var readinessLabel: String {
        switch appHealth?.readiness {
        case "ready":
            "Ready"
        case "attention":
            "Needs Attention"
        case "blocked", .none:
            "Blocked"
        default:
            appHealth?.readiness.capitalized ?? "Blocked"
        }
    }

    var lastValidationLabel: String {
        toolchainStatus?.lastValidationTime ?? "Waiting for validation"
    }

    var isShowingNewProfileWorkflow: Bool {
        activeWorkflow == .newProfile
    }

    var selectedPrinterProfile: PrinterProfileRecord? {
        guard let selectedPrinterProfileID else { return printerProfiles.first }
        return printerProfiles.first { $0.id == selectedPrinterProfileID }
    }

    var effectiveWorkflowStage: WorkflowStage {
        guard let detail = activeNewProfileDetail else { return .context }
        guard detail.stage == .blocked || detail.stage == .failed else { return detail.stage }

        if let stage = detail.commands.last?.stage {
            return stage
        }

        return detail.review != nil ? .review : detail.stage
    }

    var workflowPrimaryActionTitle: String {
        guard let detail = activeNewProfileDetail else { return "New Profile" }

        switch effectiveWorkflowStage {
        case .context:
            return "Save Context"
        case .target:
            return "Generate Target"
        case .print:
            return "Mark Chart as Printed"
        case .drying:
            return "Mark Ready to Measure"
        case .measure:
            return detail.measurement.hasMeasurementCheckpoint ? "Resume Measurement" : "Measure"
        case .build:
            return "Build Profile"
        case .review, .publish:
            return "Publish"
        case .completed:
            return detail.publishedProfileId == nil ? "Completed" : "Open in Printer Profiles"
        case .blocked, .failed:
            return detail.nextAction
        }
    }

    var canSaveWorkflowContext: Bool {
        !workflowProfileName.trimmed.isEmpty &&
            workflowSelectedPrinterID != nil &&
            workflowSelectedPaperID != nil
    }

    var canRunWorkflowPrimaryAction: Bool {
        guard let detail = activeNewProfileDetail else { return false }
        guard !detail.isCommandRunning else { return false }

        switch effectiveWorkflowStage {
        case .context:
            return canSaveWorkflowContext
        case .target:
            return parsedPatchCount > 0
        case .print:
            return true
        case .drying:
            return true
        case .measure:
            if workflowMeasurementMode == .scanFile {
                return !(effectiveScanFilePath?.isEmpty ?? true)
            }
            return true
        case .build:
            return detail.measurement.measurementSourcePath != nil
        case .review, .publish:
            return detail.review != nil
        case .completed:
            return detail.publishedProfileId != nil
        case .blocked, .failed:
            return false
        }
    }

    var workflowSelectedPrinter: PrinterRecord? {
        guard let workflowSelectedPrinterID else { return activeNewProfileDetail?.printer }
        return printers.first { $0.id == workflowSelectedPrinterID } ?? activeNewProfileDetail?.printer
    }

    var workflowSelectedPaper: PaperRecord? {
        guard let workflowSelectedPaperID else { return activeNewProfileDetail?.paper }
        return papers.first { $0.id == workflowSelectedPaperID } ?? activeNewProfileDetail?.paper
    }

    var workflowAvailableQualityModes: [String] {
        workflowSelectedPrinter?.supportedQualityModes ?? []
    }

    var cliTranscriptDetail: NewProfileJobDetail? {
        cliTranscriptState.detail
    }

    var canDeleteCurrentWorkflow: Bool {
        guard let jobId = activeNewProfileDetail?.id else { return false }
        return isActiveWorkJob(jobId: jobId)
    }

    var effectiveScanFilePath: String? {
        let explicitPath = workflowScanFilePath.trimmed
        if !explicitPath.isEmpty {
            return explicitPath
        }

        return activeNewProfileDetail?.measurement.scanFilePath
    }

    private var trimmedPathInput: String? {
        let trimmed = toolchainPathInput.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    private var parsedPatchCount: UInt32 {
        let value = UInt32(workflowPatchCount.trimmed)
        return value ?? activeNewProfileDetail?.targetSettings.patchCount ?? 0
    }

    private var parsedDryingTimeMinutes: UInt32 {
        let value = UInt32(workflowDryingTimeMinutes.trimmed)
        return value ?? activeNewProfileDetail?.printSettings.dryingTimeMinutes ?? 30
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await bootstrap()
    }

    func bootstrap() async {
        await runRefresh {
            let requestedPath = self.trimmedPathInput
            let status = await self.bridge.bootstrap(
                config: self.storagePaths.makeConfig(argyllOverridePath: requestedPath)
            )
            await self.refreshShellState(
                status: status.toolchainStatus,
                bootstrapStatus: status
            )

            if requestedPath == nil {
                self.toolchainPathInput = status.toolchainStatus.resolvedInstallPath ?? ""
            }
        }
    }

    func applyToolchainPath() async {
        await runRefresh {
            let status = await self.bridge.setToolchainPath(path: self.trimmedPathInput)
            await self.refreshShellState(
                status: status,
                bootstrapStatus: self.updatedBootstrapStatus(with: status)
            )

            if self.trimmedPathInput == nil {
                self.toolchainPathInput = status.resolvedInstallPath ?? ""
            }
        }
    }

    func clearToolchainOverride() async {
        toolchainPathInput = ""
        await applyToolchainPath()
    }

    func revalidateToolchain() async {
        await runRefresh {
            let status = await self.bridge.setToolchainPath(path: self.trimmedPathInput)
            await self.refreshShellState(
                status: status,
                bootstrapStatus: self.updatedBootstrapStatus(with: status)
            )
        }
    }

    func refreshLogs(limit: UInt32 = 200) async {
        recentLogs = await bridge.getRecentLogs(limit: limit)
    }

    func selectRoute(_ route: AppRoute) {
        selectedRoute = route
        activeWorkflow = nil

        if route == .printerProfiles && selectedPrinterProfileID == nil {
            selectedPrinterProfileID = printerProfiles.first?.id
        }
    }

    func openNewProfileWorkflow(printerId: String? = nil, paperId: String? = nil) async {
        let seed = NewProfileSeed(printerId: printerId, paperId: paperId)
        await openNewProfile(.resumableOrCreate(seed: seed))
    }

    func openActiveWorkItem(_ item: ActiveWorkItem) {
        openNewProfileJob(jobId: item.id)
    }

    func openNewProfileJob(jobId: String) {
        Task {
            await self.openNewProfile(.job(id: jobId))
        }
    }

    func openPrinterProfile(_ profile: PrinterProfileRecord) {
        selectedRoute = .printerProfiles
        activeWorkflow = nil
        selectedPrinterProfileID = profile.id
    }

    func openPublishedProfileLibrary() {
        guard let publishedProfileId = activeNewProfileDetail?.publishedProfileId else { return }
        selectedRoute = .printerProfiles
        activeWorkflow = nil
        selectedPrinterProfileID = publishedProfileId
    }

    func openCliTranscript(jobId: String) async {
        let target = CliTranscriptTarget.job(jobId: jobId)
        let preferredDetail: NewProfileJobDetail?
        if activeNewProfileDetail?.id == jobId {
            preferredDetail = activeNewProfileDetail
        } else if cliTranscriptDetail?.id == jobId {
            preferredDetail = cliTranscriptDetail
        } else {
            preferredDetail = nil
        }

        if let preferredDetail {
            cliTranscriptTarget = target
            applyCliTranscriptDetail(preferredDetail, requestedJobId: jobId, snapshot: dashboardSnapshot)
            return
        }

        setCliTranscriptLoading(target: target)
        await loadCliTranscriptDetail(jobId: jobId, snapshot: nil)
    }

    func openLatestCliTranscript() async {
        setCliTranscriptLoading(target: .latestResumable(jobId: nil))

        let snapshot = await bridge.getDashboardSnapshot()
        dashboardSnapshot = snapshot

        guard let jobId = latestResumableNewProfileJobID(from: snapshot) else {
            setCliTranscriptEmpty(target: .latestResumable(jobId: nil))
            return
        }

        cliTranscriptTarget = .latestResumable(jobId: jobId)

        if activeNewProfileDetail?.id == jobId, let detail = activeNewProfileDetail {
            applyCliTranscriptDetail(detail, requestedJobId: jobId, snapshot: snapshot)
            return
        }

        if cliTranscriptDetail?.id == jobId, let detail = cliTranscriptDetail {
            applyCliTranscriptDetail(detail, requestedJobId: jobId, snapshot: snapshot)
            return
        }

        await loadCliTranscriptDetail(jobId: jobId, snapshot: snapshot)
    }

    func requestActiveWorkDeletion(jobId: String, title: String) {
        activeWorkDeletionJobID = jobId
        activeWorkDeletionJobTitle = title
    }

    func requestActiveWorkDeletion(_ item: ActiveWorkItem) {
        requestActiveWorkDeletion(jobId: item.id, title: item.title)
    }

    func requestCurrentWorkflowDeletion() {
        guard canDeleteCurrentWorkflow, let detail = activeNewProfileDetail else { return }
        requestActiveWorkDeletion(jobId: detail.id, title: detail.title)
    }

    func cancelActiveWorkDeletion() {
        activeWorkDeletionJobID = nil
        activeWorkDeletionJobTitle = ""
    }

    func clearActiveWorkDeletionError() {
        activeWorkDeletionErrorMessage = nil
    }

    func confirmActiveWorkDeletion() async {
        guard let jobId = activeWorkDeletionJobID else { return }
        let deletedJobTitle = activeWorkDeletionJobTitle

        cancelActiveWorkDeletion()

        await runRefresh {
            let result = await self.bridge.deleteNewProfileJob(jobId: jobId)
            await self.refreshDashboardSnapshot()
            await self.refreshReferenceData()

            if result.success {
                if self.activeNewProfileDetail?.id == jobId {
                    self.activeNewProfileDetail = nil
                    self.activeWorkflow = nil
                    self.lastWorkflowEditorSeed = nil
                    self.stopWorkflowPolling()
                }

                if self.cliTranscriptTarget?.resolvedJobId == jobId || self.cliTranscriptDetail?.id == jobId {
                    self.setCliTranscriptDeleted(jobTitle: deletedJobTitle)
                }
            } else {
                self.activeWorkDeletionErrorMessage = result.message.trimmed.isEmpty
                    ? "ArgyllUX couldn't delete this unpublished work."
                    : result.message
            }
        }
    }

    func revealPathInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openPath(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func selectWorkflowPrinter(_ printerId: String?) {
        workflowSelectedPrinterID = printerId
        if let printer = printers.first(where: { $0.id == printerId }),
           workflowQualityMode.trimmed.isEmpty,
           let firstMode = printer.supportedQualityModes.first {
            workflowQualityMode = firstMode
        }
    }

    func selectWorkflowPaper(_ paperId: String?) {
        workflowSelectedPaperID = paperId
    }

    func resetSettingsPrinterDraft() {
        settingsPrinterDraft = PrinterDraft()
    }

    func resetSettingsPaperDraft() {
        settingsPaperDraft = PaperDraft()
    }

    func editPrinter(_ printer: PrinterRecord) {
        settingsPrinterDraft = PrinterDraft(record: printer)
    }

    func editPaper(_ paper: PaperRecord) {
        settingsPaperDraft = PaperDraft(record: paper)
    }

    func beginWorkflowPrinterCreation() {
        workflowPrinterDraft = PrinterDraft()
        showWorkflowPrinterForm = true
    }

    func beginWorkflowPaperCreation() {
        workflowPaperDraft = PaperDraft()
        showWorkflowPaperForm = true
    }

    func cancelWorkflowPrinterCreation() {
        workflowPrinterDraft = PrinterDraft()
        showWorkflowPrinterForm = false
    }

    func cancelWorkflowPaperCreation() {
        workflowPaperDraft = PaperDraft()
        showWorkflowPaperForm = false
    }

    func saveSettingsPrinter() async {
        await runRefresh {
            if let id = self.settingsPrinterDraft.id {
                _ = await self.bridge.updatePrinter(
                    input: UpdatePrinterInput(
                        id: id,
                        makeModel: self.settingsPrinterDraft.makeModel.trimmed,
                        nickname: self.settingsPrinterDraft.nickname.trimmed,
                        transportStyle: self.settingsPrinterDraft.transportStyle.trimmed,
                        supportedQualityModes: self.settingsPrinterDraft.supportedQualityModes,
                        monochromePathNotes: self.settingsPrinterDraft.monochromePathNotes.trimmed,
                        notes: self.settingsPrinterDraft.notes.trimmed
                    )
                )
            } else {
                _ = await self.bridge.createPrinter(
                    input: CreatePrinterInput(
                        makeModel: self.settingsPrinterDraft.makeModel.trimmed,
                        nickname: self.settingsPrinterDraft.nickname.trimmed,
                        transportStyle: self.settingsPrinterDraft.transportStyle.trimmed,
                        supportedQualityModes: self.settingsPrinterDraft.supportedQualityModes,
                        monochromePathNotes: self.settingsPrinterDraft.monochromePathNotes.trimmed,
                        notes: self.settingsPrinterDraft.notes.trimmed
                    )
                )
            }

            self.settingsPrinterDraft = PrinterDraft()
            await self.refreshReferenceData()
            await self.refreshDashboardSnapshot()
            await self.reloadActiveWorkflowIfNeeded(forceEditorSync: true)
        }
    }

    func saveSettingsPaper() async {
        await runRefresh {
            if let id = self.settingsPaperDraft.id {
                _ = await self.bridge.updatePaper(
                    input: UpdatePaperInput(
                        id: id,
                        vendorProductName: self.settingsPaperDraft.vendorProductName.trimmed,
                        surfaceClass: self.settingsPaperDraft.surfaceClass.trimmed,
                        weightThickness: self.settingsPaperDraft.weightThickness.trimmed,
                        obaFluorescenceNotes: self.settingsPaperDraft.obaFluorescenceNotes.trimmed,
                        notes: self.settingsPaperDraft.notes.trimmed
                    )
                )
            } else {
                _ = await self.bridge.createPaper(
                    input: CreatePaperInput(
                        vendorProductName: self.settingsPaperDraft.vendorProductName.trimmed,
                        surfaceClass: self.settingsPaperDraft.surfaceClass.trimmed,
                        weightThickness: self.settingsPaperDraft.weightThickness.trimmed,
                        obaFluorescenceNotes: self.settingsPaperDraft.obaFluorescenceNotes.trimmed,
                        notes: self.settingsPaperDraft.notes.trimmed
                    )
                )
            }

            self.settingsPaperDraft = PaperDraft()
            await self.refreshReferenceData()
            await self.refreshDashboardSnapshot()
            await self.reloadActiveWorkflowIfNeeded(forceEditorSync: true)
        }
    }

    func createWorkflowPrinter() async {
        guard isWorkflowPrinterDraftValid else { return }

        await runRefresh {
            let printer = await self.bridge.createPrinter(
                input: CreatePrinterInput(
                    makeModel: self.workflowPrinterDraft.makeModel.trimmed,
                    nickname: self.workflowPrinterDraft.nickname.trimmed,
                    transportStyle: self.workflowPrinterDraft.transportStyle.trimmed,
                    supportedQualityModes: self.workflowPrinterDraft.supportedQualityModes,
                    monochromePathNotes: self.workflowPrinterDraft.monochromePathNotes.trimmed,
                    notes: self.workflowPrinterDraft.notes.trimmed
                )
            )

            await self.refreshReferenceData()
            self.workflowSelectedPrinterID = printer.id
            if self.workflowQualityMode.trimmed.isEmpty,
               let firstMode = printer.supportedQualityModes.first {
                self.workflowQualityMode = firstMode
            }
            self.workflowPrinterDraft = PrinterDraft()
            self.showWorkflowPrinterForm = false
        }
    }

    func createWorkflowPaper() async {
        guard isWorkflowPaperDraftValid else { return }

        await runRefresh {
            let paper = await self.bridge.createPaper(
                input: CreatePaperInput(
                    vendorProductName: self.workflowPaperDraft.vendorProductName.trimmed,
                    surfaceClass: self.workflowPaperDraft.surfaceClass.trimmed,
                    weightThickness: self.workflowPaperDraft.weightThickness.trimmed,
                    obaFluorescenceNotes: self.workflowPaperDraft.obaFluorescenceNotes.trimmed,
                    notes: self.workflowPaperDraft.notes.trimmed
                )
            )

            await self.refreshReferenceData()
            self.workflowSelectedPaperID = paper.id
            self.workflowPaperDraft = PaperDraft()
            self.showWorkflowPaperForm = false
        }
    }

    var isWorkflowPrinterDraftValid: Bool {
        !workflowPrinterDraft.makeModel.trimmed.isEmpty
    }

    var isWorkflowPaperDraftValid: Bool {
        !workflowPaperDraft.vendorProductName.trimmed.isEmpty
    }

    func saveWorkflowContext() async {
        guard let jobId = activeNewProfileDetail?.id, canSaveWorkflowContext else { return }

        await runRefresh {
            let detail = await self.bridge.saveNewProfileContext(
                input: SaveNewProfileContextInput(
                    jobId: jobId,
                    profileName: self.workflowProfileName.trimmed,
                    printerId: self.workflowSelectedPrinterID,
                    paperId: self.workflowSelectedPaperID,
                    mediaSetting: self.workflowMediaSetting.trimmed,
                    qualityMode: self.workflowQualityMode.trimmed,
                    printPathNotes: self.workflowPrintPathNotes.trimmed,
                    measurementNotes: self.workflowMeasurementNotes.trimmed,
                    measurementObserver: self.workflowMeasurementObserver.trimmed,
                    measurementIlluminant: self.workflowMeasurementIlluminant.trimmed,
                    measurementMode: self.workflowMeasurementMode
                )
            )
            await self.handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: true)
        }
    }

    func saveTargetSettings() async {
        guard let jobId = activeNewProfileDetail?.id else { return }

        await runRefresh {
            let detail = await self.bridge.saveTargetSettings(
                input: SaveTargetSettingsInput(
                    jobId: jobId,
                    patchCount: self.parsedPatchCount,
                    improveNeutrals: self.workflowImproveNeutrals,
                    useExistingProfileToHelpTargetPlanning: self.workflowUsePlanningProfile,
                    planningProfileId: self.workflowUsePlanningProfile ? self.workflowPlanningProfileID : nil
                )
            )
            await self.handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: true)
        }
    }

    func savePrintSettings() async {
        guard let jobId = activeNewProfileDetail?.id else { return }

        await runRefresh {
            let detail = await self.bridge.savePrintSettings(
                input: SavePrintSettingsInput(
                    jobId: jobId,
                    printWithoutColorManagement: self.workflowPrintWithoutColorManagement,
                    dryingTimeMinutes: self.parsedDryingTimeMinutes
                )
            )
            await self.handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: true)
        }
    }

    func performWorkflowPrimaryAction() async {
        guard canRunWorkflowPrimaryAction else { return }

        switch effectiveWorkflowStage {
        case .context:
            await saveWorkflowContext()
        case .target:
            await generateTarget()
        case .print:
            await markChartPrinted()
        case .drying:
            await markReadyToMeasure()
        case .measure:
            await startMeasurement()
        case .build:
            await buildProfile()
        case .review, .publish:
            await publishProfile()
        case .completed:
            openPublishedProfileLibrary()
        case .blocked, .failed:
            break
        }
    }

    func generateTarget() async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        await saveTargetSettings()
        await runRefresh {
            let detail = await self.bridge.startGenerateTarget(jobId: jobId)
            await self.handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: false)
        }
    }

    func markChartPrinted() async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        await savePrintSettings()
        await runRefresh {
            let detail = await self.bridge.markNewProfilePrinted(jobId: jobId)
            await self.handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: true)
        }
    }

    func markReadyToMeasure() async {
        guard let jobId = activeNewProfileDetail?.id else { return }

        await runRefresh {
            let detail = await self.bridge.markNewProfileReadyToMeasure(jobId: jobId)
            await self.handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: true)
        }
    }

    func startMeasurement() async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        await saveWorkflowContext()

        await runRefresh {
            let detail = await self.bridge.startMeasurement(
                input: StartMeasurementInput(
                    jobId: jobId,
                    scanFilePath: self.workflowMeasurementMode == .scanFile ? self.effectiveScanFilePath : nil
                )
            )
            await self.handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: false)
        }
    }

    func buildProfile() async {
        guard let jobId = activeNewProfileDetail?.id else { return }

        await runRefresh {
            let detail = await self.bridge.startBuildProfile(jobId: jobId)
            await self.handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: false)
        }
    }

    func publishProfile() async {
        guard let jobId = activeNewProfileDetail?.id else { return }

        await runRefresh {
            let detail = await self.bridge.publishNewProfile(jobId: jobId)
            await self.handleWorkflowResult(detail, refreshProfiles: true, forceEditorSync: true)
            self.selectedPrinterProfileID = detail.publishedProfileId
        }
    }

    func startNewProfileFromSettings(printerId: String? = nil, paperId: String? = nil) {
        Task {
            await self.openNewProfileWorkflow(printerId: printerId, paperId: paperId)
        }
    }

    // Every shell-level New Profile launcher follows the same rule: resume the
    // latest resumable job first, or create a new draft if none exists. Settings
    // seeds are only applied on draft creation so a handoff cannot silently
    // rewrite another in-progress job.
    private func openNewProfile(_ target: NewProfileOpenTarget) async {
        selectedRoute = .home
        activeWorkflow = .newProfile
        showWorkflowPrinterForm = false
        showWorkflowPaperForm = false

        let snapshot = await bridge.getDashboardSnapshot()
        let printers = await bridge.listPrinters()
        let papers = await bridge.listPapers()
        let profiles = await bridge.listPrinterProfiles()
        let status: ToolchainStatus
        if let toolchainStatus {
            status = toolchainStatus
        } else {
            status = await bridge.getToolchainStatus()
        }

        let health: AppHealth
        if let appHealth {
            health = appHealth
        } else {
            health = await bridge.getAppHealth()
        }

        apply(
            status: status,
            bootstrapStatus: bootstrapStatus,
            dashboardSnapshot: snapshot,
            health: health,
            printers: printers,
            papers: papers,
            profiles: profiles
        )

        switch target {
        case let .job(jobId):
            await loadNewProfileDetail(jobId: jobId, forceEditorSync: true)
        case let .resumableOrCreate(seed):
            if let existingJobId = latestResumableNewProfileJobID(from: snapshot) {
                await loadNewProfileDetail(jobId: existingJobId, forceEditorSync: true)
                return
            }

            let detail = await bridge.createNewProfileDraft(
                input: CreateNewProfileDraftInput(
                    profileName: nil,
                    printerId: seed?.printerId,
                    paperId: seed?.paperId
                )
            )
            dashboardSnapshot = await bridge.getDashboardSnapshot()
            applyWorkflowDetail(detail, forceEditorSync: true)
        }
    }

    private func updatedBootstrapStatus(with status: ToolchainStatus) -> BootstrapStatus? {
        guard let bootstrapStatus else { return nil }
        return BootstrapStatus(
            appSupportDirReady: bootstrapStatus.appSupportDirReady,
            databaseInitialized: bootstrapStatus.databaseInitialized,
            migrationsApplied: bootstrapStatus.migrationsApplied,
            toolchainStatus: status
        )
    }

    private func refreshShellState(
        status: ToolchainStatus?,
        bootstrapStatus: BootstrapStatus?
    ) async {
        let resolvedStatus: ToolchainStatus
        if let status {
            resolvedStatus = status
        } else {
            resolvedStatus = await bridge.getToolchainStatus()
        }
        let health = await bridge.getAppHealth()
        let snapshot = await bridge.getDashboardSnapshot()
        let printers = await bridge.listPrinters()
        let papers = await bridge.listPapers()
        let profiles = await bridge.listPrinterProfiles()

        apply(
            status: resolvedStatus,
            bootstrapStatus: bootstrapStatus,
            dashboardSnapshot: snapshot,
            health: health,
            printers: printers,
            papers: papers,
            profiles: profiles
        )
    }

    private func refreshReferenceData() async {
        let printers = await bridge.listPrinters()
        let papers = await bridge.listPapers()
        let profiles = await bridge.listPrinterProfiles()
        self.printers = printers
        self.papers = papers
        self.printerProfiles = profiles

        if selectedPrinterProfileID == nil || !profiles.contains(where: { $0.id == selectedPrinterProfileID }) {
            selectedPrinterProfileID = profiles.first?.id
        }
    }

    private func refreshDashboardSnapshot() async {
        dashboardSnapshot = await bridge.getDashboardSnapshot()
    }

    private func loadNewProfileDetail(jobId: String, forceEditorSync: Bool) async {
        let detail = await bridge.getNewProfileJobDetail(jobId: jobId)
        let snapshot = await bridge.getDashboardSnapshot()
        dashboardSnapshot = snapshot
        applyWorkflowDetail(detail, forceEditorSync: forceEditorSync)
    }

    private func loadCliTranscriptDetail(jobId: String, snapshot: DashboardSnapshot?) async {
        let detail = await bridge.getNewProfileJobDetail(jobId: jobId)
        let resolvedSnapshot: DashboardSnapshot

        if let snapshot {
            resolvedSnapshot = snapshot
        } else {
            resolvedSnapshot = await bridge.getDashboardSnapshot()
            dashboardSnapshot = resolvedSnapshot
        }

        guard cliTranscriptTarget?.resolvedJobId == jobId else { return }
        applyCliTranscriptDetail(detail, requestedJobId: jobId, snapshot: resolvedSnapshot)
    }

    private func reloadActiveWorkflowIfNeeded(forceEditorSync: Bool) async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        await loadNewProfileDetail(jobId: jobId, forceEditorSync: forceEditorSync)
    }

    private func handleWorkflowResult(
        _ detail: NewProfileJobDetail,
        refreshProfiles: Bool,
        forceEditorSync: Bool
    ) async {
        await refreshDashboardSnapshot()

        if refreshProfiles {
            printerProfiles = await bridge.listPrinterProfiles()
            if selectedPrinterProfileID == nil || !printerProfiles.contains(where: { $0.id == selectedPrinterProfileID }) {
                selectedPrinterProfileID = printerProfiles.first?.id
            }
        }

        applyWorkflowDetail(detail, forceEditorSync: forceEditorSync)
    }

    private func apply(
        status: ToolchainStatus,
        bootstrapStatus: BootstrapStatus?,
        dashboardSnapshot: DashboardSnapshot,
        health: AppHealth,
        printers: [PrinterRecord],
        papers: [PaperRecord],
        profiles: [PrinterProfileRecord]
    ) {
        toolchainStatus = status
        self.bootstrapStatus = bootstrapStatus
        self.dashboardSnapshot = dashboardSnapshot
        appHealth = health
        self.printers = printers
        self.papers = papers
        printerProfiles = profiles

        if selectedPrinterProfileID == nil || !profiles.contains(where: { $0.id == selectedPrinterProfileID }) {
            selectedPrinterProfileID = profiles.first?.id
        }
    }

    private func applyWorkflowDetail(_ detail: NewProfileJobDetail, forceEditorSync: Bool) {
        activeNewProfileDetail = detail

        let seed = workflowEditorSeed(for: detail)
        if forceEditorSync || seed != lastWorkflowEditorSeed {
            syncWorkflowEditors(from: detail)
            lastWorkflowEditorSeed = seed
        }

        if detail.isCommandRunning {
            startWorkflowPollingIfNeeded()
        } else {
            stopWorkflowPolling()
        }
    }

    private func applyCliTranscriptDetail(
        _ detail: NewProfileJobDetail,
        requestedJobId: String,
        snapshot: DashboardSnapshot?
    ) {
        guard cliTranscriptTarget?.resolvedJobId == requestedJobId else { return }

        if let snapshot, isMissingCliTranscriptDetail(detail, requestedJobId: requestedJobId, snapshot: snapshot) {
            setCliTranscriptDeleted(jobTitle: nil)
            return
        }

        cliTranscriptState = .loaded(detail)

        if detail.isCommandRunning {
            startCliTranscriptPollingIfNeeded()
        } else {
            stopCliTranscriptPolling()
        }
    }

    private func syncWorkflowEditors(from detail: NewProfileJobDetail) {
        workflowProfileName = detail.profileName
        workflowSelectedPrinterID = detail.printer?.id
        workflowSelectedPaperID = detail.paper?.id
        workflowMediaSetting = detail.context.mediaSetting
        workflowQualityMode = detail.context.qualityMode
        workflowPrintPathNotes = detail.context.printPathNotes
        workflowMeasurementNotes = detail.context.measurementNotes
        workflowMeasurementObserver = detail.context.measurementObserver
        workflowMeasurementIlluminant = detail.context.measurementIlluminant
        workflowMeasurementMode = detail.context.measurementMode
        workflowPatchCount = String(detail.targetSettings.patchCount)
        workflowImproveNeutrals = detail.targetSettings.improveNeutrals
        workflowUsePlanningProfile = detail.targetSettings.useExistingProfileToHelpTargetPlanning
        workflowPlanningProfileID = detail.targetSettings.planningProfileId
        workflowPrintWithoutColorManagement = detail.printSettings.printWithoutColorManagement
        workflowDryingTimeMinutes = String(detail.printSettings.dryingTimeMinutes)
        workflowScanFilePath = detail.measurement.scanFilePath ?? ""
    }

    private func workflowEditorSeed(for detail: NewProfileJobDetail) -> String {
        "\(detail.id)|\(workflowStageIdentifier(detail.stage))"
    }

    private func latestResumableNewProfileJobID(from snapshot: DashboardSnapshot) -> String? {
        snapshot.activeWorkItems.first { $0.kind == "new_profile" }?.id
    }

    private func isActiveWorkJob(jobId: String) -> Bool {
        activeWorkItems.contains { $0.id == jobId }
    }

    private func isMissingCliTranscriptDetail(
        _ detail: NewProfileJobDetail,
        requestedJobId: String,
        snapshot: DashboardSnapshot
    ) -> Bool {
        guard detail.id == requestedJobId else { return false }
        guard !snapshot.activeWorkItems.contains(where: { $0.id == requestedJobId }) else { return false }
        guard detail.stage == .failed else { return false }

        return detail.workspacePath.isEmpty &&
            detail.profileName.isEmpty &&
            detail.printer == nil &&
            detail.paper == nil &&
            detail.commands.isEmpty
    }

    private func workflowStageIdentifier(_ stage: WorkflowStage) -> String {
        switch stage {
        case .context:
            "context"
        case .target:
            "target"
        case .print:
            "print"
        case .drying:
            "drying"
        case .measure:
            "measure"
        case .build:
            "build"
        case .review:
            "review"
        case .publish:
            "publish"
        case .completed:
            "completed"
        case .blocked:
            "blocked"
        case .failed:
            "failed"
        }
    }

    private func startWorkflowPollingIfNeeded() {
        stopWorkflowPolling()

        guard let detail = activeNewProfileDetail, detail.isCommandRunning else { return }

        workflowPollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)

                guard let currentJobId = await MainActor.run(body: { self.activeNewProfileDetail?.id }) else {
                    return
                }

                let detail = await self.bridge.getNewProfileJobDetail(jobId: currentJobId)
                let snapshot = await self.bridge.getDashboardSnapshot()

                await MainActor.run {
                    self.dashboardSnapshot = snapshot
                    self.applyWorkflowDetail(detail, forceEditorSync: false)
                }

                if !detail.isCommandRunning {
                    return
                }
            }
        }
    }

    private func startCliTranscriptPollingIfNeeded() {
        stopCliTranscriptPolling()

        guard let detail = cliTranscriptDetail, detail.isCommandRunning else { return }

        cliTranscriptPollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)

                guard let currentJobId = await MainActor.run(body: { self.cliTranscriptTarget?.resolvedJobId }) else {
                    return
                }

                let detail = await self.bridge.getNewProfileJobDetail(jobId: currentJobId)
                let snapshot = await self.bridge.getDashboardSnapshot()

                await MainActor.run {
                    self.dashboardSnapshot = snapshot
                    self.applyCliTranscriptDetail(detail, requestedJobId: currentJobId, snapshot: snapshot)
                }

                if !detail.isCommandRunning {
                    return
                }
            }
        }
    }

    private func stopWorkflowPolling() {
        workflowPollTask?.cancel()
        workflowPollTask = nil
    }

    private func stopCliTranscriptPolling() {
        cliTranscriptPollTask?.cancel()
        cliTranscriptPollTask = nil
    }

    private func setCliTranscriptLoading(target: CliTranscriptTarget) {
        cliTranscriptTarget = target
        stopCliTranscriptPolling()
        cliTranscriptState = .loading
    }

    private func setCliTranscriptEmpty(target: CliTranscriptTarget?) {
        cliTranscriptTarget = target
        stopCliTranscriptPolling()
        cliTranscriptState = .empty
    }

    private func setCliTranscriptDeleted(jobTitle: String?) {
        stopCliTranscriptPolling()
        cliTranscriptState = .deleted(jobTitle: jobTitle)
    }

    private func runRefresh(_ operation: @escaping @MainActor () async -> Void) async {
        isRefreshing = true
        await operation()
        isRefreshing = false
    }
}
