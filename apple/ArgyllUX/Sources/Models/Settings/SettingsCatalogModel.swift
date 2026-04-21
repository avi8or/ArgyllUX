import Foundation

/// Owns Settings route state for toolchain/catalog editing while delegating
/// shell-wide refresh indicators and routing back to AppModel.
@MainActor
final class SettingsCatalogModel: ObservableObject {
    @Published var toolchainStatus: ToolchainStatus?
    @Published var toolchainPathInput = ""
    @Published private(set) var printers: [PrinterRecord] = []
    @Published private(set) var papers: [PaperRecord] = []
    @Published private(set) var printerPaperPresets: [PrinterPaperPresetRecord] = []
    @Published var settingsPrinterDraft = PrinterDraft()
    @Published var settingsPaperDraft = PaperDraft()
    @Published var settingsPresetDraft = PrinterPaperPresetDraft()

    private let bridge: EngineBridge

    var shellStateRefreshRequested: ((ToolchainStatus) async -> Void)?
    var referenceDataDidChange: ((AppReferenceData) -> Void)?
    var dashboardDidChange: ((DashboardSnapshot) -> Void)?
    var workflowReloadRequested: ((Bool) async -> Void)?

    init(bridge: EngineBridge) {
        self.bridge = bridge
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

    var lastValidationLabel: String {
        toolchainStatus?.lastValidationTime ?? "Waiting for validation"
    }

    var isSettingsPresetDraftValid: Bool {
        isPresetDraftValid(settingsPresetDraft)
    }

    var trimmedPathInput: String? {
        let trimmed = toolchainPathInput.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    func applyReferenceData(_ data: AppReferenceData) {
        printers = data.printers
        papers = data.papers
        printerPaperPresets = data.printerPaperPresets
    }

    func applyToolchainStatus(_ status: ToolchainStatus?) {
        toolchainStatus = status
    }

    func applyToolchainPath() async {
        let status = await bridge.setToolchainPath(path: trimmedPathInput)
        toolchainStatus = status
        await shellStateRefreshRequested?(status)

        if trimmedPathInput == nil {
            toolchainPathInput = status.resolvedInstallPath ?? ""
        }
    }

    func clearToolchainOverride() async {
        toolchainPathInput = ""
        await applyToolchainPath()
    }

    func revalidateToolchain() async {
        let status = await bridge.setToolchainPath(path: trimmedPathInput)
        toolchainStatus = status
        await shellStateRefreshRequested?(status)
    }

    func resetSettingsPrinterDraft() {
        settingsPrinterDraft = PrinterDraft()
    }

    func resetSettingsPaperDraft() {
        settingsPaperDraft = PaperDraft()
    }

    func resetSettingsPresetDraft() {
        settingsPresetDraft = PrinterPaperPresetDraft()
    }

    func editPrinter(_ printer: PrinterRecord) {
        settingsPrinterDraft = PrinterDraft(record: printer)
    }

    func editPaper(_ paper: PaperRecord) {
        settingsPaperDraft = PaperDraft(record: paper)
    }

    func editPrinterPaperPreset(_ preset: PrinterPaperPresetRecord) {
        settingsPresetDraft = PrinterPaperPresetDraft(record: preset)
    }

    func saveSettingsPrinter() async {
        if let id = settingsPrinterDraft.id {
            _ = await bridge.updatePrinter(
                input: UpdatePrinterInput(
                    id: id,
                    manufacturer: settingsPrinterDraft.manufacturer.trimmed,
                    model: settingsPrinterDraft.model.trimmed,
                    nickname: settingsPrinterDraft.nickname.trimmed,
                    transportStyle: settingsPrinterDraft.transportStyle.trimmed,
                    colorantFamily: settingsPrinterDraft.colorantFamily,
                    channelCount: settingsPrinterDraft.normalizedChannelCount,
                    channelLabels: settingsPrinterDraft.channelLabels,
                    supportedMediaSettings: settingsPrinterDraft.supportedMediaSettings,
                    supportedQualityModes: settingsPrinterDraft.supportedQualityModes,
                    monochromePathNotes: settingsPrinterDraft.monochromePathNotes.trimmed,
                    notes: settingsPrinterDraft.notes.trimmed
                )
            )
        } else {
            _ = await bridge.createPrinter(
                input: CreatePrinterInput(
                    manufacturer: settingsPrinterDraft.manufacturer.trimmed,
                    model: settingsPrinterDraft.model.trimmed,
                    nickname: settingsPrinterDraft.nickname.trimmed,
                    transportStyle: settingsPrinterDraft.transportStyle.trimmed,
                    colorantFamily: settingsPrinterDraft.colorantFamily,
                    channelCount: settingsPrinterDraft.normalizedChannelCount,
                    channelLabels: settingsPrinterDraft.channelLabels,
                    supportedMediaSettings: settingsPrinterDraft.supportedMediaSettings,
                    supportedQualityModes: settingsPrinterDraft.supportedQualityModes,
                    monochromePathNotes: settingsPrinterDraft.monochromePathNotes.trimmed,
                    notes: settingsPrinterDraft.notes.trimmed
                )
            )
        }

        settingsPrinterDraft = PrinterDraft()
        await applyReferenceDataChange(forceWorkflowReload: true)
    }

    func saveSettingsPaper() async {
        if let id = settingsPaperDraft.id {
            _ = await bridge.updatePaper(
                input: UpdatePaperInput(
                    id: id,
                    manufacturer: settingsPaperDraft.manufacturer.trimmed,
                    paperLine: settingsPaperDraft.paperLine.trimmed,
                    surfaceClass: settingsPaperDraft.surfaceClass,
                    basisWeightValue: settingsPaperDraft.basisWeightValue.trimmed,
                    basisWeightUnit: settingsPaperDraft.basisWeightUnit,
                    thicknessValue: settingsPaperDraft.thicknessValue.trimmed,
                    thicknessUnit: settingsPaperDraft.thicknessUnit,
                    surfaceTexture: settingsPaperDraft.surfaceTexture.trimmed,
                    baseMaterial: settingsPaperDraft.baseMaterial.trimmed,
                    mediaColor: settingsPaperDraft.mediaColor.trimmed,
                    opacity: settingsPaperDraft.opacity.trimmed,
                    whiteness: settingsPaperDraft.whiteness.trimmed,
                    obaContent: settingsPaperDraft.obaContent.trimmed,
                    inkCompatibility: settingsPaperDraft.inkCompatibility.trimmed,
                    notes: settingsPaperDraft.notes.trimmed
                )
            )
        } else {
            _ = await bridge.createPaper(
                input: CreatePaperInput(
                    manufacturer: settingsPaperDraft.manufacturer.trimmed,
                    paperLine: settingsPaperDraft.paperLine.trimmed,
                    surfaceClass: settingsPaperDraft.surfaceClass,
                    basisWeightValue: settingsPaperDraft.basisWeightValue.trimmed,
                    basisWeightUnit: settingsPaperDraft.basisWeightUnit,
                    thicknessValue: settingsPaperDraft.thicknessValue.trimmed,
                    thicknessUnit: settingsPaperDraft.thicknessUnit,
                    surfaceTexture: settingsPaperDraft.surfaceTexture.trimmed,
                    baseMaterial: settingsPaperDraft.baseMaterial.trimmed,
                    mediaColor: settingsPaperDraft.mediaColor.trimmed,
                    opacity: settingsPaperDraft.opacity.trimmed,
                    whiteness: settingsPaperDraft.whiteness.trimmed,
                    obaContent: settingsPaperDraft.obaContent.trimmed,
                    inkCompatibility: settingsPaperDraft.inkCompatibility.trimmed,
                    notes: settingsPaperDraft.notes.trimmed
                )
            )
        }

        settingsPaperDraft = PaperDraft()
        await applyReferenceDataChange(forceWorkflowReload: true)
    }

    func saveSettingsPreset() async {
        guard isSettingsPresetDraftValid else { return }

        if let id = settingsPresetDraft.id {
            _ = await bridge.updatePrinterPaperPreset(
                input: UpdatePrinterPaperPresetInput(
                    id: id,
                    printerId: settingsPresetDraft.printerId ?? "",
                    paperId: settingsPresetDraft.paperId ?? "",
                    label: settingsPresetDraft.label.trimmed,
                    printPath: settingsPresetDraft.printPath.trimmed,
                    mediaSetting: settingsPresetDraft.mediaSetting.trimmed,
                    qualityMode: settingsPresetDraft.qualityMode.trimmed,
                    totalInkLimitPercent: settingsPresetDraft.totalInkLimitPercent,
                    blackInkLimitPercent: settingsPresetDraft.blackInkLimitPercent,
                    notes: settingsPresetDraft.notes.trimmed
                )
            )
        } else {
            _ = await bridge.createPrinterPaperPreset(
                input: CreatePrinterPaperPresetInput(
                    printerId: settingsPresetDraft.printerId ?? "",
                    paperId: settingsPresetDraft.paperId ?? "",
                    label: settingsPresetDraft.label.trimmed,
                    printPath: settingsPresetDraft.printPath.trimmed,
                    mediaSetting: settingsPresetDraft.mediaSetting.trimmed,
                    qualityMode: settingsPresetDraft.qualityMode.trimmed,
                    totalInkLimitPercent: settingsPresetDraft.totalInkLimitPercent,
                    blackInkLimitPercent: settingsPresetDraft.blackInkLimitPercent,
                    notes: settingsPresetDraft.notes.trimmed
                )
            )
        }

        settingsPresetDraft = PrinterPaperPresetDraft()
        await applyReferenceDataChange(forceWorkflowReload: true)
    }

    private func applyReferenceDataChange(forceWorkflowReload: Bool) async {
        let referenceData = await loadReferenceData()
        applyReferenceData(referenceData)
        referenceDataDidChange?(referenceData)
        dashboardDidChange?(await bridge.getDashboardSnapshot())

        if forceWorkflowReload {
            await workflowReloadRequested?(true)
        }
    }

    private func loadReferenceData() async -> AppReferenceData {
        AppReferenceData(
            printers: await bridge.listPrinters(),
            papers: await bridge.listPapers(),
            printerPaperPresets: await bridge.listPrinterPaperPresets(),
            printerProfiles: await bridge.listPrinterProfiles()
        )
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
}
