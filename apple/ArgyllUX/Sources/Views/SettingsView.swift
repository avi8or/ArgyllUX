import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsCatalogModel
    let storagePaths: StoragePaths
    let appHealth: AppHealth?
    let onApplyToolchainPath: () -> Void
    let onRevalidateToolchain: () -> Void
    let onClearToolchainOverride: () -> Void
    let onStartNewProfile: (String?, String?) -> Void
    let onSavePrinter: () -> Void
    let onSavePaper: () -> Void
    let onSavePreset: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 0) {
                SettingsSidebarView(settings: settings)
                    .frame(width: 300)

                Divider()

                SettingsDetailPaneView(
                    settings: settings,
                    storagePaths: storagePaths,
                    appHealth: appHealth,
                    onApplyToolchainPath: onApplyToolchainPath,
                    onRevalidateToolchain: onRevalidateToolchain,
                    onClearToolchainOverride: onClearToolchainOverride,
                    onStartNewProfile: onStartNewProfile
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $settings.activeSheet) { sheet in
            sheetView(for: sheet)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Settings")
                .font(.largeTitle.weight(.semibold))

            Spacer()

            Button("New Printer") {
                settings.presentNewPrinterSheet()
            }

            Button("New Paper") {
                settings.presentNewPaperSheet()
            }

            if showsNewPresetButton {
                Button("New Settings") {
                    settings.presentNewPresetSheet(
                        printerId: settings.selectedPrinter?.id,
                        paperId: settings.selectedPaper?.id
                    )
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var showsNewPresetButton: Bool {
        switch settings.selection ?? .toolchain {
        case .printerPaperSettings, .printerPaperSetting:
            true
        default:
            false
        }
    }

    @ViewBuilder
    private func sheetView(for sheet: SettingsCatalogSheet) -> some View {
        switch sheet {
        case .newPrinter, .editPrinter:
            PrinterEditorForm(
                title: settings.settingsPrinterDraft.title,
                draft: $settings.settingsPrinterDraft,
                saveTitle: settings.settingsPrinterDraft.id == nil ? "Save Printer" : "Save Changes",
                secondaryTitle: "Cancel",
                isSaveDisabled: !isPrinterDraftValid(settings.settingsPrinterDraft),
                onSave: onSavePrinter,
                onSecondary: {
                    settings.dismissActiveSheet()
                }
            )
        case .newPaper, .editPaper:
            PaperEditorForm(
                title: settings.settingsPaperDraft.title,
                draft: $settings.settingsPaperDraft,
                saveTitle: settings.settingsPaperDraft.id == nil ? "Save Paper" : "Save Changes",
                secondaryTitle: "Cancel",
                isSaveDisabled: !isPaperDraftValid(settings.settingsPaperDraft),
                onSave: onSavePaper,
                onSecondary: {
                    settings.dismissActiveSheet()
                }
            )
        case .newPrinterPaperSetting, .editPrinterPaperSetting:
            PrinterPaperPresetEditorForm(
                title: settings.settingsPresetDraft.title,
                draft: $settings.settingsPresetDraft,
                printers: settings.printers,
                papers: settings.papers,
                lockPrinterAndPaperSelection: false,
                saveTitle: settings.settingsPresetDraft.id == nil ? "Save Settings" : "Save Changes",
                secondaryTitle: "Cancel",
                isSaveDisabled: !settings.isSettingsPresetDraftValid,
                onSave: onSavePreset,
                onSecondary: {
                    settings.dismissActiveSheet()
                }
            )
        }
    }
}
