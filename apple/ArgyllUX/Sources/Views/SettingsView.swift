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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.largeTitle.weight(.semibold))

                ToolchainSettingsSection(
                    settings: settings,
                    onApplyToolchainPath: onApplyToolchainPath,
                    onRevalidateToolchain: onRevalidateToolchain,
                    onClearToolchainOverride: onClearToolchainOverride
                )
                StorageSettingsSection(storagePaths: storagePaths)
                PrintersSettingsSection(
                    settings: settings,
                    onStartNewProfile: onStartNewProfile,
                    onSave: onSavePrinter
                )
                PapersSettingsSection(
                    settings: settings,
                    onStartNewProfile: onStartNewProfile,
                    onSave: onSavePaper
                )
                PrinterPaperSettingsSection(settings: settings, onSave: onSavePreset)
                DefaultsSettingsSection()
                TechnicalSettingsSection(appHealth: appHealth)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
