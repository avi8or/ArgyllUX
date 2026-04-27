import Foundation
import Testing
@testable import ArgyllUX

@MainActor
struct SettingsCatalogModelTests {
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
        let model = makeSettingsModel()

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
        let model = makeSettingsModel(fakeEngine: fakeEngine)

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
    func settingsSidebarSelectionsUpdateTheSelectedCatalogItem() {
        let model = makeSettingsModel()
        let printer = makePrinter()
        let paper = makePaper()
        let preset = makePreset(printerId: printer.id, paperId: paper.id)

        model.applyReferenceData(
            AppReferenceData(
                printers: [printer],
                papers: [paper],
                printerPaperPresets: [preset],
                printerProfiles: []
            )
        )

        model.select(.storage)
        #expect(model.selection == .storage)

        model.select(.printer(printer.id))
        #expect(model.selection == .printer(printer.id))
        #expect(model.selectedPrinter?.id == printer.id)

        model.select(.paper(paper.id))
        #expect(model.selection == .paper(paper.id))
        #expect(model.selectedPaper?.id == paper.id)

        model.select(.printerPaperSetting(preset.id))
        #expect(model.selection == .printerPaperSetting(preset.id))
        #expect(model.selectedPrinterPaperPreset?.id == preset.id)
    }

    @Test
    func settingsSidebarSelectionFallsBackWhenRecordDisappears() {
        let model = makeSettingsModel()
        let printer = makePrinter()

        model.applyReferenceData(
            AppReferenceData(
                printers: [printer],
                papers: [],
                printerPaperPresets: [],
                printerProfiles: []
            )
        )
        model.select(.printer(printer.id))
        #expect(model.selection == .printer(printer.id))

        model.applyReferenceData(
            AppReferenceData(
                printers: [],
                papers: [],
                printerPaperPresets: [],
                printerProfiles: []
            )
        )

        #expect(model.selection == .printers)
    }

    @Test
    func applyToolchainPathPassesTrimmedOverride() async {
        let root = makeTemporaryRoot()
        let fakeEngine = FakeEngine()
        fakeEngine.toolchainStatusValue = makeToolchainStatus(state: .notFound, path: nil)
        fakeEngine.setToolchainPathResult = makeToolchainStatus(state: .partial, path: "/Applications/ArgyllCMS/bin")
        fakeEngine.dashboardSnapshotCurrent = makeDashboard(activeWorkItems: [])
        fakeEngine.appHealthValue = AppHealth(
            readiness: "attention",
            blockingIssues: ["ArgyllCMS is missing required tools: targen."],
            warnings: []
        )

        let model = makeAppModel(root: root, fakeEngine: fakeEngine)
        model.toolchainPathInput = "   /Applications/ArgyllCMS/bin   "
        await model.applyToolchainPath()

        #expect(fakeEngine.lastSetToolchainPath == "/Applications/ArgyllCMS/bin")
        #expect(model.toolchainStatus?.state == .partial)
        #expect(model.toolchainStatus?.resolvedInstallPath == "/Applications/ArgyllCMS/bin")
        #expect(model.bootstrapStatus == nil)
    }
}
