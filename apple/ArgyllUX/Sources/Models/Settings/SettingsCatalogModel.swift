import Foundation

enum SettingsCatalogSelection: Hashable {
    case toolchain
    case storage
    case printers
    case printer(String)
    case papers
    case paper(String)
    case printerPaperSettings
    case printerPaperSetting(String)
    case defaults
}

enum SettingsCatalogSheet: Identifiable, Equatable {
    case newPrinter
    case editPrinter(String)
    case newPaper
    case editPaper(String)
    case newPrinterPaperSetting(printerId: String?, paperId: String?)
    case editPrinterPaperSetting(String)

    var id: String {
        switch self {
        case .newPrinter:
            "new-printer"
        case let .editPrinter(id):
            "edit-printer-\(id)"
        case .newPaper:
            "new-paper"
        case let .editPaper(id):
            "edit-paper-\(id)"
        case let .newPrinterPaperSetting(printerId, paperId):
            "new-preset-\(printerId ?? "none")-\(paperId ?? "none")"
        case let .editPrinterPaperSetting(id):
            "edit-preset-\(id)"
        }
    }
}

/// Owns Settings route state for sidebar selection, modal catalog editing, and
/// toolchain configuration while delegating shell-wide refresh indicators back
/// to AppModel.
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
    @Published var selection: SettingsCatalogSelection? = .toolchain
    @Published var activeSheet: SettingsCatalogSheet?

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

    var selectedPrinter: PrinterRecord? {
        guard case let .printer(id)? = selection else { return nil }
        return printers.first(where: { $0.id == id })
    }

    var selectedPaper: PaperRecord? {
        guard case let .paper(id)? = selection else { return nil }
        return papers.first(where: { $0.id == id })
    }

    var selectedPrinterPaperPreset: PrinterPaperPresetRecord? {
        guard case let .printerPaperSetting(id)? = selection else { return nil }
        return printerPaperPresets.first(where: { $0.id == id })
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
        selection = validatedSelection(selection)
    }

    func applyToolchainStatus(_ status: ToolchainStatus?) {
        toolchainStatus = status
    }

    func select(_ selection: SettingsCatalogSelection) {
        self.selection = validatedSelection(selection)
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

    func dismissActiveSheet() {
        activeSheet = nil
        resetSettingsPrinterDraft()
        resetSettingsPaperDraft()
        resetSettingsPresetDraft()
    }

    func presentNewPrinterSheet() {
        resetSettingsPrinterDraft()
        selection = .printers
        activeSheet = .newPrinter
    }

    func presentEditPrinterSheet(_ printer: PrinterRecord? = nil) {
        guard let printer = printer ?? selectedPrinter else { return }
        settingsPrinterDraft = PrinterDraft(record: printer)
        selection = .printer(printer.id)
        activeSheet = .editPrinter(printer.id)
    }

    func presentNewPaperSheet() {
        resetSettingsPaperDraft()
        selection = .papers
        activeSheet = .newPaper
    }

    func presentEditPaperSheet(_ paper: PaperRecord? = nil) {
        guard let paper = paper ?? selectedPaper else { return }
        settingsPaperDraft = PaperDraft(record: paper)
        selection = .paper(paper.id)
        activeSheet = .editPaper(paper.id)
    }

    func presentNewPresetSheet(printerId: String? = nil, paperId: String? = nil) {
        resetSettingsPresetDraft()
        settingsPresetDraft.printerId = printerId ?? selectedPrinter?.id
        settingsPresetDraft.paperId = paperId ?? selectedPaper?.id
        sanitizePrinterPaperPresetDraft(&settingsPresetDraft, printers: printers)
        selection = .printerPaperSettings
        activeSheet = .newPrinterPaperSetting(
            printerId: settingsPresetDraft.printerId,
            paperId: settingsPresetDraft.paperId
        )
    }

    func presentEditPresetSheet(_ preset: PrinterPaperPresetRecord? = nil) {
        guard let preset = preset ?? selectedPrinterPaperPreset else { return }
        settingsPresetDraft = PrinterPaperPresetDraft(record: preset)
        selection = .printerPaperSetting(preset.id)
        activeSheet = .editPrinterPaperSetting(preset.id)
    }

    func editPrinter(_ printer: PrinterRecord) {
        presentEditPrinterSheet(printer)
    }

    func editPaper(_ paper: PaperRecord) {
        presentEditPaperSheet(paper)
    }

    func editPrinterPaperPreset(_ preset: PrinterPaperPresetRecord) {
        presentEditPresetSheet(preset)
    }

    func saveSettingsPrinter() async {
        let savedPrinter: PrinterRecord

        if let id = settingsPrinterDraft.id {
            savedPrinter = await bridge.updatePrinter(
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
            savedPrinter = await bridge.createPrinter(
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
        activeSheet = nil
        selection = .printer(savedPrinter.id)
        await applyReferenceDataChange(forceWorkflowReload: true)
    }

    func saveSettingsPaper() async {
        let savedPaper: PaperRecord

        if let id = settingsPaperDraft.id {
            savedPaper = await bridge.updatePaper(
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
            savedPaper = await bridge.createPaper(
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
        activeSheet = nil
        selection = .paper(savedPaper.id)
        await applyReferenceDataChange(forceWorkflowReload: true)
    }

    func saveSettingsPreset() async {
        guard isSettingsPresetDraftValid else { return }

        let savedPreset: PrinterPaperPresetRecord
        if let id = settingsPresetDraft.id {
            savedPreset = await bridge.updatePrinterPaperPreset(
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
            savedPreset = await bridge.createPrinterPaperPreset(
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
        activeSheet = nil
        selection = .printerPaperSetting(savedPreset.id)
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

    private func validatedSelection(_ selection: SettingsCatalogSelection?) -> SettingsCatalogSelection {
        guard let selection else { return .toolchain }

        switch selection {
        case .toolchain, .storage, .printers, .papers, .printerPaperSettings, .defaults:
            return selection
        case let .printer(id):
            return printers.contains(where: { $0.id == id }) ? selection : .printers
        case let .paper(id):
            return papers.contains(where: { $0.id == id }) ? selection : .papers
        case let .printerPaperSetting(id):
            return printerPaperPresets.contains(where: { $0.id == id }) ? selection : .printerPaperSettings
        }
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
