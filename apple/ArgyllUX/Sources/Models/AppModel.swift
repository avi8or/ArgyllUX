import Combine
import Foundation

enum WorkflowDestination: Equatable {
    case newProfile
}

// Keep destructive flows in one shell-level model so workflow, footer, and
// library surfaces share the same confirmation and error presentation rules.
private enum PendingDeletion: Equatable, Sendable {
    case activeWork(jobId: String, title: String)
    case printerProfile(profileId: String, profileName: String, sourceJobId: String)

    var actionTitle: String {
        switch self {
        case .activeWork:
            return ActiveWorkCopy.deleteActionTitle
        case .printerProfile:
            return PrinterProfileCopy.deleteActionTitle
        }
    }

    var confirmationMessage: String {
        switch self {
        case let .activeWork(jobId, title):
            return ActiveWorkCopy.deletionConfirmationMessage(jobTitle: title, jobId: jobId)
        case let .printerProfile(_, profileName, _):
            return PrinterProfileCopy.deletionConfirmationMessage(profileName: profileName)
        }
    }

    var errorTitle: String {
        switch self {
        case .activeWork:
            return ActiveWorkCopy.deleteErrorTitle
        case .printerProfile:
            return PrinterProfileCopy.deleteErrorTitle
        }
    }

    var fallbackErrorMessage: String {
        switch self {
        case .activeWork:
            return "ArgyllUX couldn't delete this unpublished work."
        case .printerProfile:
            return "ArgyllUX couldn't delete this Printer Profile."
        }
    }
}

private struct DeletionErrorState: Equatable {
    let title: String
    let message: String
}

enum ShellRouteAccessory: Equatable {
    case none
    case workflowManaged
}

struct ShellChromeConfiguration: Equatable {
    let routeAccessory: ShellRouteAccessory
    let showsRightInspector: Bool
    let showsActiveWorkDock: Bool
    let showsFooterStatusBar: Bool

    static let standard = ShellChromeConfiguration(
        routeAccessory: .none,
        showsRightInspector: true,
        showsActiveWorkDock: true,
        showsFooterStatusBar: true
    )

    static let workflow = ShellChromeConfiguration(
        routeAccessory: .workflowManaged,
        showsRightInspector: true,
        showsActiveWorkDock: true,
        showsFooterStatusBar: true
    )
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedRoute: AppRoute = .home
    @Published var activeWorkflow: WorkflowDestination?
    @Published var bootstrapStatus: BootstrapStatus?
    @Published var dashboardSnapshot: DashboardSnapshot?
    @Published var appHealth: AppHealth?
    @Published var recentLogs: [LogEntry] = []
    @Published private var pendingDeletion: PendingDeletion?
    @Published private var deletionError: DeletionErrorState?
    @Published var isRefreshing = false

    let launcherActions: [LauncherAction] = [
        LauncherAction(
            title: "New Profile",
            detail: "Create a printer profile from a printed and measured target.",
            status: "Available",
            kind: .newProfile
        ),
        LauncherAction(
            title: "Troubleshoot",
            detail: "Start from a visible print problem and collect evidence.",
            status: "Entry screen",
            kind: .route(.troubleshoot)
        ),
        LauncherAction(
            title: "Inspect",
            detail: "Review measurements, gamuts, and profile internals.",
            status: "Entry screen",
            kind: .route(.inspect)
        ),
        LauncherAction(
            title: "B&W Tuning",
            detail: "Review monochrome neutrality and tonal behavior.",
            status: "Entry screen",
            kind: .route(.blackAndWhiteTuning)
        ),
        LauncherAction(
            title: "Improve Profile",
            detail: "Add better data to an existing profile.",
            status: "Planned",
            kind: .planned
        ),
        LauncherAction(
            title: "Import Profile",
            detail: "Bring a finished ICC profile into the library.",
            status: "Planned",
            kind: .planned
        ),
        LauncherAction(
            title: "Import Measurements",
            detail: "Bring raw measurement data into analysis or follow-up work.",
            status: "Planned",
            kind: .planned
        ),
        LauncherAction(
            title: "Match a Reference",
            detail: "Push output toward a known reference condition.",
            status: "Planned",
            kind: .planned
        ),
        LauncherAction(
            title: "Verify Output",
            detail: "Check whether current output is still trustworthy.",
            status: "Planned",
            kind: .planned
        ),
        LauncherAction(
            title: "Recalibrate",
            detail: "Restore a previously trusted calibrated state.",
            status: "Planned",
            kind: .planned
        ),
        LauncherAction(
            title: "Rebuild",
            detail: "Create a new characterization when assumptions changed.",
            status: "Planned",
            kind: .planned
        ),
        LauncherAction(
            title: "Spot Measure",
            detail: "Capture individual color readings as evidence.",
            status: "Planned",
            kind: .planned
        ),
        LauncherAction(
            title: "Compare Measurements",
            detail: "Compare current readings to a trusted baseline.",
            status: "Planned",
            kind: .planned
        ),
    ]

    let storagePaths: StoragePaths
    let settings: SettingsCatalogModel
    let workflow: NewProfileWorkflowModel
    let profileLibrary: ProfileLibraryModel
    let cliTranscript: CliTranscriptModel

    private let bridge: EngineBridge
    private let fileOpener: FileOpening
    private var hasBootstrapped = false
    private var cancellables = Set<AnyCancellable>()

    init(
        storagePaths: StoragePaths = .default(),
        engine: EngineProtocol = Engine(),
        fileOpener: FileOpening = FileOpener()
    ) {
        self.storagePaths = storagePaths
        self.bridge = EngineBridge(engine: engine)
        self.fileOpener = fileOpener
        settings = SettingsCatalogModel(bridge: bridge)
        workflow = NewProfileWorkflowModel(bridge: bridge, fileOpener: fileOpener)
        profileLibrary = ProfileLibraryModel()
        cliTranscript = CliTranscriptModel(bridge: bridge, fileOpener: fileOpener)

        configureFeatureModels()
        observeFeatureModels()
    }

    var toolchainStatus: ToolchainStatus? {
        settings.toolchainStatus
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
        settings.argyllVersionLabel
    }

    var toolchainPathInput: String {
        get { settings.toolchainPathInput }
        set { settings.toolchainPathInput = newValue }
    }

    var argyllStatusLabel: String {
        settings.argyllStatusLabel
    }

    var detectedToolchainPath: String {
        settings.detectedToolchainPath
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

    var readinessTone: StatusBadgeView.Tone {
        switch appHealth?.readiness {
        case "ready":
            .ready
        case "attention":
            .attention
        case "blocked", .none:
            .blocked
        default:
            .blocked
        }
    }

    var toolchainTone: StatusBadgeView.Tone {
        switch toolchainStatus?.state {
        case .ready:
            .ready
        case .partial:
            .attention
        case .notFound, .none:
            .blocked
        }
    }

    var lastValidationLabel: String {
        settings.lastValidationLabel
    }

    var isShowingNewProfileWorkflow: Bool {
        activeWorkflow == .newProfile
    }

    var shellChromeConfiguration: ShellChromeConfiguration {
        if isShowingNewProfileWorkflow {
            return .workflow
        }

        return .standard
    }

    var availableLauncherActions: [LauncherAction] {
        launcherActions.filter(\.isEnabled)
    }

    var plannedLauncherActions: [LauncherAction] {
        launcherActions.filter { !$0.isEnabled }
    }

    var shellJumpItems: [ShellJumpItem] {
        var items = AppRoute.allCases.map { route in
            ShellJumpItem(
                title: route.title,
                subtitle: route.jumpSubtitle,
                systemImage: route.symbolName,
                destination: .route(route)
            )
        }

        items.append(contentsOf: activeWorkItems.map { item in
            ShellJumpItem(
                title: item.title,
                subtitle: "Active work - \(workflowStageDisplayTitle(item.stage)) - \(workflowNextActionDisplayTitle(stage: item.stage, rawTitle: item.nextAction))",
                systemImage: "clock.arrow.circlepath",
                destination: .newProfileJob(item.id)
            )
        })

        items.append(contentsOf: printerProfiles.map { profile in
            ShellJumpItem(
                title: profile.name,
                subtitle: "Printer Profile - \(profile.printerName) / \(profile.paperName)",
                systemImage: "printer",
                destination: .printerProfile(profile.id)
            )
        })

        items.append(contentsOf: settings.printers.map { printer in
            ShellJumpItem(
                title: printer.displayName,
                subtitle: "Printer settings",
                systemImage: "printer",
                destination: .settings(.printer(printer.id))
            )
        })

        items.append(contentsOf: settings.papers.map { paper in
            ShellJumpItem(
                title: paper.displayName,
                subtitle: "Paper settings",
                systemImage: "doc.text",
                destination: .settings(.paper(paper.id))
            )
        })

        return items
    }

    var printers: [PrinterRecord] {
        settings.printers
    }

    var papers: [PaperRecord] {
        settings.papers
    }

    var printerPaperPresets: [PrinterPaperPresetRecord] {
        settings.printerPaperPresets
    }

    var printerProfiles: [PrinterProfileRecord] {
        profileLibrary.printerProfiles
    }

    var selectedPrinterProfileID: String? {
        get { profileLibrary.selectedPrinterProfileID }
        set { profileLibrary.selectedPrinterProfileID = newValue }
    }

    var selectedPrinterProfile: PrinterProfileRecord? {
        profileLibrary.selectedPrinterProfile
    }

    var settingsPrinterDraft: PrinterDraft {
        get { settings.settingsPrinterDraft }
        set { settings.settingsPrinterDraft = newValue }
    }

    var settingsPaperDraft: PaperDraft {
        get { settings.settingsPaperDraft }
        set { settings.settingsPaperDraft = newValue }
    }

    var settingsPresetDraft: PrinterPaperPresetDraft {
        get { settings.settingsPresetDraft }
        set { settings.settingsPresetDraft = newValue }
    }

    var isSettingsPresetDraftValid: Bool {
        settings.isSettingsPresetDraftValid
    }

    var activeNewProfileDetail: NewProfileJobDetail? {
        workflow.activeNewProfileDetail
    }

    var workflowProfileName: String {
        get { workflow.workflowProfileName }
        set { workflow.workflowProfileName = newValue }
    }

    var workflowSelectedPrinterID: String? {
        get { workflow.workflowSelectedPrinterID }
        set { workflow.workflowSelectedPrinterID = newValue }
    }

    var workflowSelectedPaperID: String? {
        get { workflow.workflowSelectedPaperID }
        set { workflow.workflowSelectedPaperID = newValue }
    }

    var workflowSelectedPrinterPaperPresetID: String? {
        get { workflow.workflowSelectedPrinterPaperPresetID }
        set { workflow.workflowSelectedPrinterPaperPresetID = newValue }
    }

    var workflowPrintPath: String {
        get { workflow.workflowPrintPath }
        set { workflow.workflowPrintPath = newValue }
    }

    var workflowMediaSetting: String {
        get { workflow.workflowMediaSetting }
        set { workflow.workflowMediaSetting = newValue }
    }

    var workflowQualityMode: String {
        get { workflow.workflowQualityMode }
        set { workflow.workflowQualityMode = newValue }
    }

    var workflowPrintPathNotes: String {
        get { workflow.workflowPrintPathNotes }
        set { workflow.workflowPrintPathNotes = newValue }
    }

    var workflowMeasurementNotes: String {
        get { workflow.workflowMeasurementNotes }
        set { workflow.workflowMeasurementNotes = newValue }
    }

    var workflowMeasurementObserver: String {
        get { workflow.workflowMeasurementObserver }
        set { workflow.workflowMeasurementObserver = newValue }
    }

    var workflowMeasurementIlluminant: String {
        get { workflow.workflowMeasurementIlluminant }
        set { workflow.workflowMeasurementIlluminant = newValue }
    }

    var workflowMeasurementMode: MeasurementMode {
        get { workflow.workflowMeasurementMode }
        set { workflow.workflowMeasurementMode = newValue }
    }

    var workflowPatchCount: String {
        get { workflow.workflowPatchCount }
        set { workflow.workflowPatchCount = newValue }
    }

    var workflowImproveNeutrals: Bool {
        get { workflow.workflowImproveNeutrals }
        set { workflow.workflowImproveNeutrals = newValue }
    }

    var workflowUsePlanningProfile: Bool {
        get { workflow.workflowUsePlanningProfile }
        set { workflow.workflowUsePlanningProfile = newValue }
    }

    var workflowPlanningProfileID: String? {
        get { workflow.workflowPlanningProfileID }
        set { workflow.workflowPlanningProfileID = newValue }
    }

    var workflowPrintWithoutColorManagement: Bool {
        get { workflow.workflowPrintWithoutColorManagement }
        set { workflow.workflowPrintWithoutColorManagement = newValue }
    }

    var workflowDryingTimeMinutes: String {
        get { workflow.workflowDryingTimeMinutes }
        set { workflow.workflowDryingTimeMinutes = newValue }
    }

    var workflowScanFilePath: String {
        get { workflow.workflowScanFilePath }
        set { workflow.workflowScanFilePath = newValue }
    }

    var workflowPrinterDraft: PrinterDraft {
        get { workflow.workflowPrinterDraft }
        set { workflow.workflowPrinterDraft = newValue }
    }

    var workflowPaperDraft: PaperDraft {
        get { workflow.workflowPaperDraft }
        set { workflow.workflowPaperDraft = newValue }
    }

    var workflowPresetDraft: PrinterPaperPresetDraft {
        get { workflow.workflowPresetDraft }
        set { workflow.workflowPresetDraft = newValue }
    }

    var effectiveWorkflowStage: WorkflowStage {
        workflow.effectiveWorkflowStage
    }

    var workflowPrimaryActionTitle: String {
        workflow.workflowPrimaryActionTitle
    }

    var canSaveWorkflowContext: Bool {
        workflow.canSaveWorkflowContext
    }

    var canRunWorkflowPrimaryAction: Bool {
        workflow.canRunWorkflowPrimaryAction
    }

    var workflowSelectedPrinter: PrinterRecord? {
        workflow.workflowSelectedPrinter
    }

    var workflowSelectedPaper: PaperRecord? {
        workflow.workflowSelectedPaper
    }

    var workflowSelectedPrinterPaperPreset: PrinterPaperPresetRecord? {
        workflow.workflowSelectedPrinterPaperPreset
    }

    var workflowAvailablePrinterPaperPresets: [PrinterPaperPresetRecord] {
        workflow.workflowAvailablePrinterPaperPresets
    }

    var workflowAvailableMediaSettings: [String] {
        workflow.workflowAvailableMediaSettings
    }

    var workflowAvailableQualityModes: [String] {
        workflow.workflowAvailableQualityModes
    }

    var workflowSelectedPrinterHasBlackChannel: Bool {
        workflow.workflowSelectedPrinterHasBlackChannel
    }

    var workflowHasLegacyContextWithoutPreset: Bool {
        workflow.workflowHasLegacyContextWithoutPreset
    }

    var showsWorkflowStandalonePrintPathEditor: Bool {
        workflow.showsWorkflowStandalonePrintPathEditor
    }

    var currentWorkflowDeletionActionTitle: String? {
        workflow.currentWorkflowDeletionActionTitle
    }

    var canDeleteCurrentWorkflow: Bool {
        workflow.canDeleteCurrentWorkflow
    }

    var effectiveScanFilePath: String? {
        workflow.effectiveScanFilePath
    }

    var isWorkflowPrinterDraftValid: Bool {
        workflow.isWorkflowPrinterDraftValid
    }

    var isWorkflowPaperDraftValid: Bool {
        workflow.isWorkflowPaperDraftValid
    }

    var isWorkflowPresetDraftValid: Bool {
        workflow.isWorkflowPresetDraftValid
    }

    var cliTranscriptTarget: CliTranscriptTarget? {
        cliTranscript.cliTranscriptTarget
    }

    var cliTranscriptState: CliTranscriptState {
        cliTranscript.cliTranscriptState
    }

    var cliTranscriptDetail: NewProfileJobDetail? {
        cliTranscript.cliTranscriptDetail
    }

    var isShowingDeletionConfirmation: Bool {
        pendingDeletion != nil
    }

    var deletionConfirmationTitle: String {
        pendingDeletion?.actionTitle ?? ActiveWorkCopy.deleteActionTitle
    }

    var deletionConfirmationMessage: String {
        pendingDeletion?.confirmationMessage ?? ""
    }

    var isShowingDeletionError: Bool {
        deletionError != nil
    }

    var deletionErrorTitle: String {
        deletionError?.title ?? ActiveWorkCopy.deleteErrorTitle
    }

    var deletionErrorMessage: String? {
        deletionError?.message
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await bootstrap()
    }

    func bootstrap() async {
        await runRefresh {
            let requestedPath = self.settings.trimmedPathInput
            let status = await self.bridge.bootstrap(
                config: self.storagePaths.makeConfig(argyllOverridePath: requestedPath)
            )
            await self.refreshShellState(
                status: status.toolchainStatus,
                bootstrapStatus: status
            )

            if requestedPath == nil {
                self.settings.toolchainPathInput = status.toolchainStatus.resolvedInstallPath ?? ""
            }
        }
    }

    func applyToolchainPath() async {
        await runRefresh {
            await self.settings.applyToolchainPath()
        }
    }

    func clearToolchainOverride() async {
        await runRefresh {
            await self.settings.clearToolchainOverride()
        }
    }

    func revalidateToolchain() async {
        await runRefresh {
            await self.settings.revalidateToolchain()
        }
    }

    func refreshLogs(limit: UInt32 = 200) async {
        recentLogs = await bridge.getRecentLogs(limit: limit)
    }

    func selectRoute(_ route: AppRoute) {
        selectedRoute = route
        activeWorkflow = nil

        if route == .printerProfiles, profileLibrary.selectedPrinterProfileID == nil {
            profileLibrary.selectProfile(id: profileLibrary.printerProfiles.first?.id)
        }
    }

    func openJumpItem(_ item: ShellJumpItem) {
        switch item.destination {
        case let .route(route):
            selectRoute(route)
        case let .newProfileJob(jobId):
            openNewProfileJob(jobId: jobId)
        case let .printerProfile(profileId):
            selectedRoute = .printerProfiles
            activeWorkflow = nil
            profileLibrary.selectProfile(id: profileId)
        case let .settings(selection):
            selectedRoute = .settings
            activeWorkflow = nil
            settings.select(selection)
        }
    }

    func openNewProfileWorkflow(printerId: String? = nil, paperId: String? = nil) async {
        selectedRoute = .home
        activeWorkflow = .newProfile
        await refreshShellState(status: settings.toolchainStatus, bootstrapStatus: bootstrapStatus)
        await workflow.openNewProfileWorkflow(printerId: printerId, paperId: paperId)
    }

    func openActiveWorkItem(_ item: ActiveWorkItem) {
        openNewProfileJob(jobId: item.id)
    }

    func openNewProfileJob(jobId: String) {
        Task {
            self.selectedRoute = .home
            self.activeWorkflow = .newProfile
            await self.workflow.openNewProfileJob(jobId: jobId)
        }
    }

    func openPrinterProfile(_ profile: PrinterProfileRecord) {
        selectedRoute = .printerProfiles
        activeWorkflow = nil
        profileLibrary.selectProfile(profile)
    }

    func openPublishedProfileLibrary() {
        openPublishedProfileLibrary(profileId: workflow.activeNewProfileDetail?.publishedProfileId)
    }

    func openCliTranscript(jobId: String) async {
        await cliTranscript.openCliTranscript(
            jobId: jobId,
            activeDetail: workflow.activeNewProfileDetail,
            dashboardSnapshot: dashboardSnapshot
        )
    }

    func openLatestCliTranscript() async {
        await cliTranscript.openLatestCliTranscript(activeDetail: workflow.activeNewProfileDetail)
    }

    func requestActiveWorkDeletion(jobId: String, title: String) {
        pendingDeletion = .activeWork(jobId: jobId, title: title)
    }

    func requestActiveWorkDeletion(_ item: ActiveWorkItem) {
        requestActiveWorkDeletion(jobId: item.id, title: item.title)
    }

    func requestSelectedPrinterProfileDeletion() {
        guard let profile = profileLibrary.selectedPrinterProfile else { return }
        pendingDeletion = .printerProfile(
            profileId: profile.id,
            profileName: profile.name,
            sourceJobId: profile.createdFromJobId
        )
    }

    func requestCurrentWorkflowDeletion() {
        guard workflow.canDeleteCurrentWorkflow, let detail = workflow.activeNewProfileDetail else { return }

        if let publishedProfileId = detail.publishedProfileId {
            let profileName = detail.profileName.trimmed.isEmpty ? detail.title : detail.profileName
            pendingDeletion = .printerProfile(
                profileId: publishedProfileId,
                profileName: profileName,
                sourceJobId: detail.id
            )
            return
        }

        requestActiveWorkDeletion(jobId: detail.id, title: detail.title)
    }

    func cancelPendingDeletion() {
        pendingDeletion = nil
    }

    func clearDeletionError() {
        deletionError = nil
    }

    @discardableResult
    func confirmPendingDeletion() -> Task<Void, Never>? {
        guard let pendingDeletion else { return nil }

        self.pendingDeletion = nil

        return Task {
            await self.performPendingDeletion(pendingDeletion)
        }
    }

    private func performPendingDeletion(_ pendingDeletion: PendingDeletion) async {
        await runRefresh {
            switch pendingDeletion {
            case let .activeWork(jobId, title):
                let result = await self.bridge.deleteNewProfileJob(jobId: jobId)
                await self.applyLatestShellData()

                if result.success {
                    self.workflow.clearAfterDeletedActiveWork(jobId: jobId)
                    if self.workflow.activeNewProfileDetail == nil {
                        self.activeWorkflow = nil
                    }

                    if self.cliTranscript.cliTranscriptTarget?.resolvedJobId == jobId || self.cliTranscript.cliTranscriptDetail?.id == jobId {
                        self.cliTranscript.setDeleted(jobTitle: title)
                    }
                } else {
                    self.deletionError = DeletionErrorState(
                        title: pendingDeletion.errorTitle,
                        message: result.message.trimmed.isEmpty ? pendingDeletion.fallbackErrorMessage : result.message
                    )
                }
            case let .printerProfile(profileId, _, sourceJobId):
                let result = await self.bridge.deletePrinterProfile(profileId: profileId)
                await self.applyLatestShellData()

                if result.success {
                    if self.workflow.activeNewProfileDetail?.id == sourceJobId {
                        await self.workflow.reloadActiveWorkflowIfNeeded(forceEditorSync: false)
                    }

                    await self.cliTranscript.reloadTranscriptIfTracking(jobId: sourceJobId, snapshot: self.dashboardSnapshot)
                } else {
                    self.deletionError = DeletionErrorState(
                        title: pendingDeletion.errorTitle,
                        message: result.message.trimmed.isEmpty ? pendingDeletion.fallbackErrorMessage : result.message
                    )
                }
            }
        }
    }

    func revealPathInFinder(_ path: String) {
        fileOpener.revealPathInFinder(path)
    }

    func openPath(_ path: String) {
        fileOpener.openPath(path)
    }

    func saveSettingsPrinter() async {
        await runRefresh {
            await self.settings.saveSettingsPrinter()
        }
    }

    func resetSettingsPrinterDraft() {
        settings.resetSettingsPrinterDraft()
    }

    func resetSettingsPaperDraft() {
        settings.resetSettingsPaperDraft()
    }

    func resetSettingsPresetDraft() {
        settings.resetSettingsPresetDraft()
    }

    func editPrinter(_ printer: PrinterRecord) {
        settings.editPrinter(printer)
    }

    func editPaper(_ paper: PaperRecord) {
        settings.editPaper(paper)
    }

    func editPrinterPaperPreset(_ preset: PrinterPaperPresetRecord) {
        settings.editPrinterPaperPreset(preset)
    }

    func saveSettingsPaper() async {
        await runRefresh {
            await self.settings.saveSettingsPaper()
        }
    }

    func saveSettingsPreset() async {
        await runRefresh {
            await self.settings.saveSettingsPreset()
        }
    }

    func createWorkflowPrinter() async {
        await runRefresh {
            await self.workflow.createWorkflowPrinter()
        }
    }

    func selectWorkflowPrinter(_ printerId: String?) {
        workflow.selectWorkflowPrinter(printerId)
    }

    func selectWorkflowPaper(_ paperId: String?) {
        workflow.selectWorkflowPaper(paperId)
    }

    func selectWorkflowPrinterPaperPreset(_ presetId: String?) {
        workflow.selectWorkflowPrinterPaperPreset(presetId)
    }

    func beginWorkflowPrinterCreation() {
        workflow.beginWorkflowPrinterCreation()
    }

    func beginWorkflowPaperCreation() {
        workflow.beginWorkflowPaperCreation()
    }

    func beginWorkflowPresetCreation() {
        workflow.beginWorkflowPresetCreation()
    }

    func cancelWorkflowPrinterCreation() {
        workflow.cancelWorkflowPrinterCreation()
    }

    func cancelWorkflowPaperCreation() {
        workflow.cancelWorkflowPaperCreation()
    }

    func cancelWorkflowPresetCreation() {
        workflow.cancelWorkflowPresetCreation()
    }

    func createWorkflowPaper() async {
        await runRefresh {
            await self.workflow.createWorkflowPaper()
        }
    }

    func createWorkflowPreset() async {
        await runRefresh {
            await self.workflow.createWorkflowPreset()
        }
    }

    func saveWorkflowContext() async {
        await runRefresh {
            await self.workflow.saveWorkflowContext()
        }
    }

    func saveTargetSettings() async {
        await runRefresh {
            await self.workflow.saveTargetSettings()
        }
    }

    func savePrintSettings() async {
        await runRefresh {
            await self.workflow.savePrintSettings()
        }
    }

    func performWorkflowPrimaryAction() async {
        let initialStage = workflow.effectiveWorkflowStage
        await runRefresh {
            await self.workflow.performWorkflowPrimaryAction()
        }

        if initialStage == .completed,
           workflow.activeNewProfileDetail?.publishedProfileId != nil {
            openPublishedProfileLibrary()
        }
    }

    func generateTarget() async {
        await runRefresh {
            await self.workflow.generateTarget()
        }
    }

    func markChartPrinted() async {
        await runRefresh {
            await self.workflow.markChartPrinted()
        }
    }

    func markReadyToMeasure() async {
        await runRefresh {
            await self.workflow.markReadyToMeasure()
        }
    }

    func startMeasurement() async {
        await runRefresh {
            await self.workflow.startMeasurement()
        }
    }

    func buildProfile() async {
        await runRefresh {
            await self.workflow.buildProfile()
        }
    }

    func publishProfile() async {
        await runRefresh {
            await self.workflow.publishProfile()
        }
    }

    func startNewProfileFromSettings(printerId: String? = nil, paperId: String? = nil) {
        Task {
            await self.openNewProfileWorkflow(printerId: printerId, paperId: paperId)
        }
    }

    private func configureFeatureModels() {
        settings.shellStateRefreshRequested = { [weak self] status in
            guard let self else { return }
            await self.refreshShellState(
                status: status,
                bootstrapStatus: self.updatedBootstrapStatus(with: status)
            )
        }
        settings.referenceDataDidChange = { [weak self] data in
            self?.applyReferenceData(data)
        }
        settings.dashboardDidChange = { [weak self] snapshot in
            self?.applyDashboardSnapshot(snapshot)
        }
        settings.workflowReloadRequested = { [weak self] forceEditorSync in
            guard let self else { return }
            await self.workflow.reloadActiveWorkflowIfNeeded(forceEditorSync: forceEditorSync)
        }

        workflow.dashboardDidChange = { [weak self] snapshot in
            self?.applyDashboardSnapshot(snapshot)
        }
        workflow.referenceDataDidChange = { [weak self] data in
            self?.applyReferenceData(data)
        }
        workflow.publishedProfileDidChange = { [weak self] profileId in
            self?.profileLibrary.selectProfile(id: profileId)
        }

        cliTranscript.dashboardDidChange = { [weak self] snapshot in
            self?.applyDashboardSnapshot(snapshot)
        }
        cliTranscript.showJobRequested = { [weak self] jobId in
            self?.openNewProfileJob(jobId: jobId)
        }
    }

    private func observeFeatureModels() {
        observe(settings)
        observe(workflow)
        observe(profileLibrary)
        observe(cliTranscript)
    }

    private func observe(_ featureModel: some ObservableObject) {
        featureModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    private func loadReferenceData() async -> AppReferenceData {
        AppReferenceData(
            printers: await bridge.listPrinters(),
            papers: await bridge.listPapers(),
            printerPaperPresets: await bridge.listPrinterPaperPresets(),
            printerProfiles: await bridge.listPrinterProfiles()
        )
    }

    private func applyReferenceData(_ data: AppReferenceData) {
        settings.applyReferenceData(data)
        workflow.applyReferenceData(data)
        profileLibrary.applyReferenceData(data)
    }

    private func applyDashboardSnapshot(_ snapshot: DashboardSnapshot) {
        dashboardSnapshot = snapshot
        workflow.applyActiveWorkItems(snapshot.activeWorkItems)
    }

    private func applyLatestShellData() async {
        let snapshot = await bridge.getDashboardSnapshot()
        let referenceData = await loadReferenceData()
        applyDashboardSnapshot(snapshot)
        applyReferenceData(referenceData)
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
        let referenceData = await loadReferenceData()

        settings.applyToolchainStatus(resolvedStatus)
        self.bootstrapStatus = bootstrapStatus
        appHealth = health
        applyDashboardSnapshot(snapshot)
        applyReferenceData(referenceData)
    }

    private func openPublishedProfileLibrary(profileId: String?) {
        guard let profileId else { return }
        selectedRoute = .printerProfiles
        activeWorkflow = nil
        profileLibrary.selectProfile(id: profileId)
    }

    private func runRefresh(_ operation: @escaping @MainActor () async -> Void) async {
        isRefreshing = true
        await operation()
        isRefreshing = false
    }
}
