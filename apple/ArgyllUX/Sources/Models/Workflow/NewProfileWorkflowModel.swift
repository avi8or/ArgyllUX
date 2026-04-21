import Foundation

private struct NewProfileSeed: Equatable {
    let printerId: String?
    let paperId: String?
}

private enum NewProfileOpenTarget: Equatable {
    case resumableOrCreate(seed: NewProfileSeed?)
    case job(id: String)
}

/// Owns New Profile editor state, inline catalog creation, and workflow polling
/// while leaving shell routing and destructive confirmation UI to AppModel.
@MainActor
final class NewProfileWorkflowModel: ObservableObject {
    @Published var activeNewProfileDetail: NewProfileJobDetail?
    @Published private(set) var printers: [PrinterRecord] = []
    @Published private(set) var papers: [PaperRecord] = []
    @Published private(set) var printerPaperPresets: [PrinterPaperPresetRecord] = []
    @Published private(set) var printerProfiles: [PrinterProfileRecord] = []
    @Published var workflowProfileName = ""
    @Published var workflowSelectedPrinterID: String?
    @Published var workflowSelectedPaperID: String?
    @Published var workflowSelectedPrinterPaperPresetID: String?
    @Published var workflowPrintPath = ""
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
    @Published var showWorkflowPrinterForm = false
    @Published var showWorkflowPaperForm = false
    @Published var showWorkflowPresetForm = false
    @Published var workflowPrinterDraft = PrinterDraft()
    @Published var workflowPaperDraft = PaperDraft()
    @Published var workflowPresetDraft = PrinterPaperPresetDraft()

    private let bridge: EngineBridge
    private let fileOpener: FileOpening
    private var workflowPollTask: Task<Void, Never>?
    private var lastWorkflowEditorSeed: String?
    private var activeWorkJobIDs = Set<String>()

    var dashboardDidChange: ((DashboardSnapshot) -> Void)?
    var referenceDataDidChange: ((AppReferenceData) -> Void)?
    var publishedProfileDidChange: ((String?) -> Void)?

    init(bridge: EngineBridge, fileOpener: FileOpening) {
        self.bridge = bridge
        self.fileOpener = fileOpener
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
            workflowSelectedPaperID != nil &&
            !workflowMediaSetting.trimmed.isEmpty &&
            !workflowQualityMode.trimmed.isEmpty
    }

    var canRunWorkflowPrimaryAction: Bool {
        guard let detail = activeNewProfileDetail else { return false }
        guard !detail.isCommandRunning else { return false }

        switch effectiveWorkflowStage {
        case .context:
            return canSaveWorkflowContext
        case .target:
            return parsedPatchCount > 0
        case .print, .drying:
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

    var workflowSelectedPrinterPaperPreset: PrinterPaperPresetRecord? {
        guard let workflowSelectedPrinterPaperPresetID else { return nil }
        return printerPaperPresets.first { $0.id == workflowSelectedPrinterPaperPresetID }
    }

    var workflowAvailablePrinterPaperPresets: [PrinterPaperPresetRecord] {
        guard let printerID = workflowSelectedPrinterID, let paperID = workflowSelectedPaperID else { return [] }
        return printerPaperPresets.filter { $0.printerId == printerID && $0.paperId == paperID }
    }

    var workflowAvailableMediaSettings: [String] {
        workflowSelectedPrinter?.supportedMediaSettings ?? []
    }

    var workflowAvailableQualityModes: [String] {
        workflowSelectedPrinter?.supportedQualityModes ?? []
    }

    var workflowSelectedPrinterHasBlackChannel: Bool {
        guard let printer = workflowSelectedPrinter else { return false }
        return printer.colorantFamily.hasBlackChannel(channelLabels: printer.channelLabels)
    }

    var workflowHasLegacyContextWithoutPreset: Bool {
        guard let detail = activeNewProfileDetail else { return false }
        return detail.context.printerPaperPresetId == nil &&
            (!detail.context.printPath.isEmpty ||
                !detail.context.mediaSetting.isEmpty ||
                !detail.context.qualityMode.isEmpty)
    }

    var showsWorkflowStandalonePrintPathEditor: Bool {
        workflowSelectedPrinterPaperPreset == nil && !showWorkflowPresetForm
    }

    var canDeleteCurrentWorkflow: Bool {
        currentWorkflowDeletionActionTitle != nil
    }

    var currentWorkflowDeletionActionTitle: String? {
        guard let detail = activeNewProfileDetail else { return nil }

        if detail.publishedProfileId != nil {
            return PrinterProfileCopy.deleteActionTitle
        }

        guard activeWorkJobIDs.contains(detail.id) else { return nil }
        return ActiveWorkCopy.deleteActionTitle
    }

    var effectiveScanFilePath: String? {
        let explicitPath = workflowScanFilePath.trimmed
        if !explicitPath.isEmpty {
            return explicitPath
        }

        return activeNewProfileDetail?.measurement.scanFilePath
    }

    var isWorkflowPrinterDraftValid: Bool {
        isPrinterDraftValid(workflowPrinterDraft)
    }

    var isWorkflowPaperDraftValid: Bool {
        isPaperDraftValid(workflowPaperDraft)
    }

    var isWorkflowPresetDraftValid: Bool {
        isPresetDraftValid(workflowPresetDraft)
    }

    func applyReferenceData(_ data: AppReferenceData) {
        printers = data.printers
        papers = data.papers
        printerPaperPresets = data.printerPaperPresets
        printerProfiles = data.printerProfiles
    }

    func applyActiveWorkItems(_ items: [ActiveWorkItem]) {
        activeWorkJobIDs = Set(items.map(\.id))
    }

    func clearAfterDeletedActiveWork(jobId: String) {
        guard activeNewProfileDetail?.id == jobId else { return }
        activeNewProfileDetail = nil
        lastWorkflowEditorSeed = nil
        stopWorkflowPolling()
    }

    func revealPathInFinder(_ path: String) {
        fileOpener.revealPathInFinder(path)
    }

    func openPath(_ path: String) {
        fileOpener.openPath(path)
    }

    func openNewProfileWorkflow(printerId: String? = nil, paperId: String? = nil) async {
        let seed = NewProfileSeed(printerId: printerId, paperId: paperId)
        await openNewProfile(.resumableOrCreate(seed: seed))
    }

    func openNewProfileJob(jobId: String) async {
        await openNewProfile(.job(id: jobId))
    }

    func reloadActiveWorkflowIfNeeded(forceEditorSync: Bool) async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        await loadNewProfileDetail(jobId: jobId, forceEditorSync: forceEditorSync)
    }

    func selectWorkflowPrinter(_ printerId: String?) {
        workflowSelectedPrinterID = printerId
        syncWorkflowPresetDraftToCurrentSelection()
        syncWorkflowPresetSelectionAfterContextChange(autoSelect: true)
    }

    func selectWorkflowPaper(_ paperId: String?) {
        workflowSelectedPaperID = paperId
        syncWorkflowPresetDraftToCurrentSelection()
        syncWorkflowPresetSelectionAfterContextChange(autoSelect: true)
    }

    func selectWorkflowPrinterPaperPreset(_ presetId: String?) {
        workflowSelectedPrinterPaperPresetID = presetId
        if let preset = workflowSelectedPrinterPaperPreset {
            populateWorkflowContext(from: preset)
        } else if !workflowHasLegacyContextWithoutPreset {
            workflowPrintPath = ""
            workflowMediaSetting = ""
            workflowQualityMode = ""
        }
    }

    func beginWorkflowPrinterCreation() {
        workflowPrinterDraft = PrinterDraft()
        showWorkflowPrinterForm = true
    }

    func beginWorkflowPaperCreation() {
        workflowPaperDraft = PaperDraft()
        showWorkflowPaperForm = true
    }

    func beginWorkflowPresetCreation() {
        workflowPresetDraft = PrinterPaperPresetDraft()
        workflowPresetDraft.printerId = workflowSelectedPrinterID
        workflowPresetDraft.paperId = workflowSelectedPaperID
        workflowPresetDraft.printPath = workflowPrintPath
        workflowPresetDraft.mediaSetting = workflowMediaSetting
        workflowPresetDraft.qualityMode = workflowQualityMode
        sanitizePrinterPaperPresetDraft(&workflowPresetDraft, printers: printers)
        showWorkflowPresetForm = true
    }

    func cancelWorkflowPrinterCreation() {
        workflowPrinterDraft = PrinterDraft()
        showWorkflowPrinterForm = false
    }

    func cancelWorkflowPaperCreation() {
        workflowPaperDraft = PaperDraft()
        showWorkflowPaperForm = false
    }

    func cancelWorkflowPresetCreation() {
        workflowPresetDraft = PrinterPaperPresetDraft()
        showWorkflowPresetForm = false
    }

    func createWorkflowPrinter() async {
        guard isWorkflowPrinterDraftValid else { return }

        let printer = await bridge.createPrinter(
            input: CreatePrinterInput(
                manufacturer: workflowPrinterDraft.manufacturer.trimmed,
                model: workflowPrinterDraft.model.trimmed,
                nickname: workflowPrinterDraft.nickname.trimmed,
                transportStyle: workflowPrinterDraft.transportStyle.trimmed,
                colorantFamily: workflowPrinterDraft.colorantFamily,
                channelCount: workflowPrinterDraft.normalizedChannelCount,
                channelLabels: workflowPrinterDraft.channelLabels,
                supportedMediaSettings: workflowPrinterDraft.supportedMediaSettings,
                supportedQualityModes: workflowPrinterDraft.supportedQualityModes,
                monochromePathNotes: workflowPrinterDraft.monochromePathNotes.trimmed,
                notes: workflowPrinterDraft.notes.trimmed
            )
        )

        let data = await loadReferenceData()
        applyReferenceData(data)
        referenceDataDidChange?(data)
        selectWorkflowPrinter(printer.id)
        workflowPrinterDraft = PrinterDraft()
        showWorkflowPrinterForm = false
    }

    func createWorkflowPaper() async {
        guard isWorkflowPaperDraftValid else { return }

        let paper = await bridge.createPaper(
            input: CreatePaperInput(
                manufacturer: workflowPaperDraft.manufacturer.trimmed,
                paperLine: workflowPaperDraft.paperLine.trimmed,
                surfaceClass: workflowPaperDraft.surfaceClass,
                basisWeightValue: workflowPaperDraft.basisWeightValue.trimmed,
                basisWeightUnit: workflowPaperDraft.basisWeightUnit,
                thicknessValue: workflowPaperDraft.thicknessValue.trimmed,
                thicknessUnit: workflowPaperDraft.thicknessUnit,
                surfaceTexture: workflowPaperDraft.surfaceTexture.trimmed,
                baseMaterial: workflowPaperDraft.baseMaterial.trimmed,
                mediaColor: workflowPaperDraft.mediaColor.trimmed,
                opacity: workflowPaperDraft.opacity.trimmed,
                whiteness: workflowPaperDraft.whiteness.trimmed,
                obaContent: workflowPaperDraft.obaContent.trimmed,
                inkCompatibility: workflowPaperDraft.inkCompatibility.trimmed,
                notes: workflowPaperDraft.notes.trimmed
            )
        )

        let data = await loadReferenceData()
        applyReferenceData(data)
        referenceDataDidChange?(data)
        selectWorkflowPaper(paper.id)
        workflowPaperDraft = PaperDraft()
        showWorkflowPaperForm = false
    }

    func createWorkflowPreset() async {
        guard isWorkflowPresetDraftValid else { return }

        let preset = await bridge.createPrinterPaperPreset(
            input: CreatePrinterPaperPresetInput(
                printerId: workflowPresetDraft.printerId ?? "",
                paperId: workflowPresetDraft.paperId ?? "",
                label: workflowPresetDraft.label.trimmed,
                printPath: workflowPresetDraft.printPath.trimmed,
                mediaSetting: workflowPresetDraft.mediaSetting.trimmed,
                qualityMode: workflowPresetDraft.qualityMode.trimmed,
                totalInkLimitPercent: workflowPresetDraft.totalInkLimitPercent,
                blackInkLimitPercent: workflowPresetDraft.blackInkLimitPercent,
                notes: workflowPresetDraft.notes.trimmed
            )
        )

        let data = await loadReferenceData()
        applyReferenceData(data)
        referenceDataDidChange?(data)
        selectWorkflowPrinterPaperPreset(preset.id)
        workflowPresetDraft = PrinterPaperPresetDraft()
        showWorkflowPresetForm = false
    }

    func saveWorkflowContext() async {
        guard let jobId = activeNewProfileDetail?.id, canSaveWorkflowContext else { return }

        let detail = await bridge.saveNewProfileContext(
            input: SaveNewProfileContextInput(
                jobId: jobId,
                profileName: workflowProfileName.trimmed,
                printerId: workflowSelectedPrinterID,
                paperId: workflowSelectedPaperID,
                printerPaperPresetId: workflowSelectedPrinterPaperPresetID,
                printPath: workflowPrintPath.trimmed,
                mediaSetting: workflowMediaSetting.trimmed,
                qualityMode: workflowQualityMode.trimmed,
                printPathNotes: workflowPrintPathNotes.trimmed,
                measurementNotes: workflowMeasurementNotes.trimmed,
                measurementObserver: workflowMeasurementObserver.trimmed,
                measurementIlluminant: workflowMeasurementIlluminant.trimmed,
                measurementMode: workflowMeasurementMode
            )
        )
        await handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: true)
    }

    func saveTargetSettings() async {
        guard let jobId = activeNewProfileDetail?.id else { return }

        let detail = await bridge.saveTargetSettings(
            input: SaveTargetSettingsInput(
                jobId: jobId,
                patchCount: parsedPatchCount,
                improveNeutrals: workflowImproveNeutrals,
                useExistingProfileToHelpTargetPlanning: workflowUsePlanningProfile,
                planningProfileId: workflowUsePlanningProfile ? workflowPlanningProfileID : nil
            )
        )
        await handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: true)
    }

    func savePrintSettings() async {
        guard let jobId = activeNewProfileDetail?.id else { return }

        let detail = await bridge.savePrintSettings(
            input: SavePrintSettingsInput(
                jobId: jobId,
                printWithoutColorManagement: workflowPrintWithoutColorManagement,
                dryingTimeMinutes: parsedDryingTimeMinutes
            )
        )
        await handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: true)
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
        case .completed, .blocked, .failed:
            break
        }
    }

    func generateTarget() async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        await saveTargetSettings()
        let detail = await bridge.startGenerateTarget(jobId: jobId)
        await handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: false)
    }

    func markChartPrinted() async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        await savePrintSettings()
        let detail = await bridge.markNewProfilePrinted(jobId: jobId)
        await handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: true)
    }

    func markReadyToMeasure() async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        let detail = await bridge.markNewProfileReadyToMeasure(jobId: jobId)
        await handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: true)
    }

    func startMeasurement() async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        await saveWorkflowContext()

        let detail = await bridge.startMeasurement(
            input: StartMeasurementInput(
                jobId: jobId,
                scanFilePath: workflowMeasurementMode == .scanFile ? effectiveScanFilePath : nil
            )
        )
        await handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: false)
    }

    func buildProfile() async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        let detail = await bridge.startBuildProfile(jobId: jobId)
        await handleWorkflowResult(detail, refreshProfiles: false, forceEditorSync: false)
    }

    func publishProfile() async {
        guard let jobId = activeNewProfileDetail?.id else { return }
        let detail = await bridge.publishNewProfile(jobId: jobId)
        await handleWorkflowResult(detail, refreshProfiles: true, forceEditorSync: true)
        publishedProfileDidChange?(detail.publishedProfileId)
    }

    private var parsedPatchCount: UInt32 {
        let value = UInt32(workflowPatchCount.trimmed)
        return value ?? activeNewProfileDetail?.targetSettings.patchCount ?? 0
    }

    private var parsedDryingTimeMinutes: UInt32 {
        let value = UInt32(workflowDryingTimeMinutes.trimmed)
        return value ?? activeNewProfileDetail?.printSettings.dryingTimeMinutes ?? 30
    }

    // Every shell-level New Profile launcher follows the same rule: resume the
    // latest resumable job first, or create a new draft if none exists. Settings
    // seeds are only applied on draft creation so a handoff cannot silently
    // rewrite another in-progress job.
    private func openNewProfile(_ target: NewProfileOpenTarget) async {
        let snapshot = await bridge.getDashboardSnapshot()
        dashboardDidChange?(snapshot)
        applyActiveWorkItems(snapshot.activeWorkItems)

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
            let updatedSnapshot = await bridge.getDashboardSnapshot()
            dashboardDidChange?(updatedSnapshot)
            applyActiveWorkItems(updatedSnapshot.activeWorkItems)
            applyWorkflowDetail(detail, forceEditorSync: true)
        }
    }

    private func handleWorkflowResult(
        _ detail: NewProfileJobDetail,
        refreshProfiles: Bool,
        forceEditorSync: Bool
    ) async {
        let snapshot = await bridge.getDashboardSnapshot()
        dashboardDidChange?(snapshot)
        applyActiveWorkItems(snapshot.activeWorkItems)

        if refreshProfiles {
            let data = await loadReferenceData()
            applyReferenceData(data)
            referenceDataDidChange?(data)
        }

        applyWorkflowDetail(detail, forceEditorSync: forceEditorSync)
    }

    private func loadNewProfileDetail(jobId: String, forceEditorSync: Bool) async {
        let detail = await bridge.getNewProfileJobDetail(jobId: jobId)
        let snapshot = await bridge.getDashboardSnapshot()
        dashboardDidChange?(snapshot)
        applyActiveWorkItems(snapshot.activeWorkItems)
        applyWorkflowDetail(detail, forceEditorSync: forceEditorSync)
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

    private func syncWorkflowEditors(from detail: NewProfileJobDetail) {
        workflowProfileName = detail.profileName
        workflowSelectedPrinterID = detail.printer?.id
        workflowSelectedPaperID = detail.paper?.id
        workflowSelectedPrinterPaperPresetID = detail.context.printerPaperPresetId
        workflowPrintPath = detail.context.printPath
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
        syncWorkflowPresetSelectionAfterContextChange(autoSelect: false)
    }

    private func workflowEditorSeed(for detail: NewProfileJobDetail) -> String {
        [
            detail.id,
            workflowStageIdentifier(detail.stage),
            detail.printer?.id ?? "",
            detail.paper?.id ?? "",
            detail.context.printerPaperPresetId ?? "",
            detail.context.printPath,
            detail.context.mediaSetting,
            detail.context.qualityMode,
        ].joined(separator: "|")
    }

    private func isPresetDraftValid(_ draft: PrinterPaperPresetDraft) -> Bool {
        guard let printerID = draft.printerId, let paperID = draft.paperId else { return false }
        guard let printer = printers.first(where: { $0.id == printerID }) else { return false }
        guard papers.contains(where: { $0.id == paperID }) else { return false }

        let mediaSetting = draft.mediaSetting.trimmed
        let qualityMode = draft.qualityMode.trimmed
        guard !mediaSetting.isEmpty, !qualityMode.isEmpty else { return false }
        guard printer.supportedMediaSettings.contains(mediaSetting) else { return false }
        guard printer.supportedQualityModes.contains(qualityMode) else { return false }

        if !draft.totalInkLimitPercentText.trimmed.isEmpty {
            guard let totalInkLimitPercent = draft.totalInkLimitPercent, (1 ... 400).contains(totalInkLimitPercent) else {
                return false
            }
        }

        if !draft.blackInkLimitPercentText.trimmed.isEmpty {
            guard let blackInkLimitPercent = draft.blackInkLimitPercent, (1 ... 100).contains(blackInkLimitPercent) else {
                return false
            }
            guard printer.colorantFamily.hasBlackChannel(channelLabels: printer.channelLabels) else {
                return false
            }
        }

        return true
    }

    // While inline preset creation is open, the workflow's outer printer and
    // paper pickers remain the authoritative pair selection.
    private func syncWorkflowPresetDraftToCurrentSelection() {
        guard showWorkflowPresetForm else { return }
        guard let printerId = workflowSelectedPrinterID, let paperId = workflowSelectedPaperID else {
            cancelWorkflowPresetCreation()
            return
        }

        workflowPresetDraft.printerId = printerId
        workflowPresetDraft.paperId = paperId
        sanitizePrinterPaperPresetDraft(&workflowPresetDraft, printers: printers)
    }

    private func populateWorkflowContext(from preset: PrinterPaperPresetRecord) {
        workflowPrintPath = preset.printPath
        workflowMediaSetting = preset.mediaSetting
        workflowQualityMode = preset.qualityMode
    }

    private func syncWorkflowPresetSelectionAfterContextChange(autoSelect: Bool) {
        let matchingPresets = workflowAvailablePrinterPaperPresets
        if let currentPresetID = workflowSelectedPrinterPaperPresetID,
           let preset = matchingPresets.first(where: { $0.id == currentPresetID })
        {
            populateWorkflowContext(from: preset)
            return
        }

        workflowSelectedPrinterPaperPresetID = nil

        if autoSelect, let firstPreset = matchingPresets.first {
            workflowSelectedPrinterPaperPresetID = firstPreset.id
            populateWorkflowContext(from: firstPreset)
            return
        }

        if !workflowAvailableMediaSettings.isEmpty,
           !workflowAvailableMediaSettings.contains(workflowMediaSetting)
        {
            workflowMediaSetting = ""
        }

        if !workflowAvailableQualityModes.isEmpty,
           !workflowAvailableQualityModes.contains(workflowQualityMode)
        {
            workflowQualityMode = ""
        }

        if !workflowHasLegacyContextWithoutPreset && workflowSelectedPrinterPaperPresetID == nil {
            workflowPrintPath = ""
        }
    }

    private func latestResumableNewProfileJobID(from snapshot: DashboardSnapshot) -> String? {
        snapshot.activeWorkItems.first { $0.kind == "new_profile" }?.id
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
                    self.dashboardDidChange?(snapshot)
                    self.applyActiveWorkItems(snapshot.activeWorkItems)
                    self.applyWorkflowDetail(detail, forceEditorSync: false)
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

    private func loadReferenceData() async -> AppReferenceData {
        AppReferenceData(
            printers: await bridge.listPrinters(),
            papers: await bridge.listPapers(),
            printerPaperPresets: await bridge.listPrinterPaperPresets(),
            printerProfiles: await bridge.listPrinterProfiles()
        )
    }
}
