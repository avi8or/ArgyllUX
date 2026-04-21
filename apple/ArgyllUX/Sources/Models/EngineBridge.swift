import Foundation

actor EngineBridge {
    private let engine: EngineProtocol

    init(engine: EngineProtocol = Engine()) {
        self.engine = engine
    }

    func bootstrap(config: EngineConfig) -> BootstrapStatus {
        engine.bootstrap(config: config)
    }

    func getToolchainStatus() -> ToolchainStatus {
        engine.getToolchainStatus()
    }

    func setToolchainPath(path: String?) -> ToolchainStatus {
        engine.setToolchainPath(path: path)
    }

    func getAppHealth() -> AppHealth {
        engine.getAppHealth()
    }

    func getDashboardSnapshot() -> DashboardSnapshot {
        engine.getDashboardSnapshot()
    }

    func getRecentLogs(limit: UInt32) -> [LogEntry] {
        engine.getRecentLogs(limit: limit)
    }

    func listPrinters() -> [PrinterRecord] {
        engine.listPrinters()
    }

    func createPrinter(input: CreatePrinterInput) -> PrinterRecord {
        engine.createPrinter(input: input)
    }

    func updatePrinter(input: UpdatePrinterInput) -> PrinterRecord {
        engine.updatePrinter(input: input)
    }

    func listPapers() -> [PaperRecord] {
        engine.listPapers()
    }

    func createPaper(input: CreatePaperInput) -> PaperRecord {
        engine.createPaper(input: input)
    }

    func updatePaper(input: UpdatePaperInput) -> PaperRecord {
        engine.updatePaper(input: input)
    }

    func listPrinterPaperPresets() -> [PrinterPaperPresetRecord] {
        engine.listPrinterPaperPresets()
    }

    func createPrinterPaperPreset(input: CreatePrinterPaperPresetInput) -> PrinterPaperPresetRecord {
        engine.createPrinterPaperPreset(input: input)
    }

    func updatePrinterPaperPreset(input: UpdatePrinterPaperPresetInput) -> PrinterPaperPresetRecord {
        engine.updatePrinterPaperPreset(input: input)
    }

    func listPrinterProfiles() -> [PrinterProfileRecord] {
        engine.listPrinterProfiles()
    }

    func createNewProfileDraft(input: CreateNewProfileDraftInput) -> NewProfileJobDetail {
        engine.createNewProfileDraft(input: input)
    }

    func getNewProfileJobDetail(jobId: String) -> NewProfileJobDetail {
        engine.getNewProfileJobDetail(jobId: jobId)
    }

    func saveNewProfileContext(input: SaveNewProfileContextInput) -> NewProfileJobDetail {
        engine.saveNewProfileContext(input: input)
    }

    func saveTargetSettings(input: SaveTargetSettingsInput) -> NewProfileJobDetail {
        engine.saveTargetSettings(input: input)
    }

    func savePrintSettings(input: SavePrintSettingsInput) -> NewProfileJobDetail {
        engine.savePrintSettings(input: input)
    }

    func startGenerateTarget(jobId: String) -> NewProfileJobDetail {
        engine.startGenerateTarget(jobId: jobId)
    }

    func markNewProfilePrinted(jobId: String) -> NewProfileJobDetail {
        engine.markNewProfilePrinted(jobId: jobId)
    }

    func markNewProfileReadyToMeasure(jobId: String) -> NewProfileJobDetail {
        engine.markNewProfileReadyToMeasure(jobId: jobId)
    }

    func startMeasurement(input: StartMeasurementInput) -> NewProfileJobDetail {
        engine.startMeasurement(input: input)
    }

    func startBuildProfile(jobId: String) -> NewProfileJobDetail {
        engine.startBuildProfile(jobId: jobId)
    }

    func publishNewProfile(jobId: String) -> NewProfileJobDetail {
        engine.publishNewProfile(jobId: jobId)
    }

    func deleteNewProfileJob(jobId: String) -> DeleteResult {
        engine.deleteNewProfileJob(jobId: jobId)
    }

    func deletePrinterProfile(profileId: String) -> DeleteResult {
        engine.deletePrinterProfile(profileId: profileId)
    }
}
