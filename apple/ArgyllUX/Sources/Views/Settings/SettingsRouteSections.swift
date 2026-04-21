import SwiftUI

struct ToolchainSettingsSection: View {
    @ObservedObject var settings: SettingsCatalogModel
    let onApplyToolchainPath: () -> Void
    let onRevalidateToolchain: () -> Void
    let onClearToolchainOverride: () -> Void

    private var toolchainTone: StatusBadgeView.Tone {
        switch settings.toolchainStatus?.state {
        case .ready:
            .ready
        case .partial:
            .attention
        case .notFound, .none:
            .blocked
        }
    }

    var body: some View {
        settingsSection("Argyll") {
            VStack(alignment: .leading, spacing: 14) {
                OperationalDetailRow(title: "Detected path", value: settings.detectedToolchainPath)

                HStack {
                    Text("Status")
                    Spacer()
                    StatusBadgeView(title: settings.argyllStatusLabel, tone: toolchainTone)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose Path")
                        .font(AppTypography.detailLabel)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        TextField("Choose Path", text: $settings.toolchainPathInput)
                            .textFieldStyle(.roundedBorder)

                        Button("Choose Path") {
                            if let selectedPath = PathSelection.chooseDirectory(initialPath: settings.toolchainPathInput) {
                                settings.toolchainPathInput = selectedPath
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Apply Path", action: onApplyToolchainPath)

                        Button("Re-run Validation", action: onRevalidateToolchain)

                        Button("Clear Override", action: onClearToolchainOverride)
                        .disabled(settings.toolchainPathInput.isEmpty)
                    }
                }

                if let toolchainStatus = settings.toolchainStatus, !toolchainStatus.missingExecutables.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Missing tools")
                            .font(AppTypography.detailLabel)
                            .foregroundStyle(.secondary)
                        Text(toolchainStatus.missingExecutables.joined(separator: ", "))
                            .font(AppTypography.detailValue)
                    }
                }
            }
        }
    }
}

struct StorageSettingsSection: View {
    let storagePaths: StoragePaths

    var body: some View {
        settingsSection("Storage") {
            VStack(alignment: .leading, spacing: 12) {
                OperationalDetailRow(title: "App support path", value: storagePaths.appSupportPath)
                OperationalDetailRow(title: "Database path", value: storagePaths.databasePath)
                OperationalDetailRow(title: "Log path", value: storagePaths.logPath)
            }
        }
    }
}

struct PrintersSettingsSection: View {
    @ObservedObject var settings: SettingsCatalogModel
    let onStartNewProfile: (String?, String?) -> Void
    let onSave: () -> Void

    var body: some View {
        settingsSection("Printers") {
            VStack(alignment: .leading, spacing: 16) {
                if settings.printers.isEmpty {
                    settingsEmptyState("Create a printer here or inline from New Profile.")
                } else {
                    ForEach(settings.printers, id: \.id) { printer in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(printer.displayName)
                                        .font(.headline)
                                    Text(structuredPrinterIdentity(printer))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(channelSetupSummary(printer.colorantFamily, printer.channelCount, printer.channelLabels))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    if !printer.transportStyle.isEmpty {
                                        Text("Transport: \(printer.transportStyle)")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                HStack(spacing: 10) {
                                    Button("Use in New Profile") {
                                        onStartNewProfile(printer.id, nil)
                                    }

                                    Button("Edit") {
                                        settings.editPrinter(printer)
                                    }
                                }
                            }

                            if !printer.supportedMediaSettings.isEmpty {
                                detailLine(title: "Media settings", value: printer.supportedMediaSettings.joined(separator: ", "))
                            }

                            if !printer.supportedQualityModes.isEmpty {
                                detailLine(title: "Quality modes", value: printer.supportedQualityModes.joined(separator: ", "))
                            }

                            if !printer.notes.isEmpty {
                                Text(printer.notes)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                PrinterEditorForm(
                    title: settings.settingsPrinterDraft.title,
                    draft: $settings.settingsPrinterDraft,
                    saveTitle: settings.settingsPrinterDraft.id == nil ? "Create Printer" : "Save Printer",
                    secondaryTitle: "Reset",
                    isSaveDisabled: !isPrinterDraftValid(settings.settingsPrinterDraft),
                    onSave: onSave,
                    onSecondary: {
                        settings.resetSettingsPrinterDraft()
                    }
                )
            }
        }
    }
}

struct PapersSettingsSection: View {
    @ObservedObject var settings: SettingsCatalogModel
    let onStartNewProfile: (String?, String?) -> Void
    let onSave: () -> Void

    var body: some View {
        settingsSection("Papers") {
            VStack(alignment: .leading, spacing: 16) {
                if settings.papers.isEmpty {
                    settingsEmptyState("Create a paper here or inline from New Profile.")
                } else {
                    ForEach(settings.papers, id: \.id) { paper in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(paper.displayName)
                                        .font(.headline)
                                    Text(structuredPaperIdentity(paper))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if let surfaceSummary = paperSurfaceSummary(paper) {
                                        Text(surfaceSummary)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let specsSummary = paperSpecsSummary(paper) {
                                        Text(specsSummary)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let detailsSummary = paperDetailsSummary(paper) {
                                        Text(detailsSummary)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                HStack(spacing: 10) {
                                    Button("Use in New Profile") {
                                        onStartNewProfile(nil, paper.id)
                                    }

                                    Button("Edit") {
                                        settings.editPaper(paper)
                                    }
                                }
                            }

                            if !paper.notes.isEmpty {
                                Text(paper.notes)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                PaperEditorForm(
                    title: settings.settingsPaperDraft.title,
                    draft: $settings.settingsPaperDraft,
                    saveTitle: settings.settingsPaperDraft.id == nil ? "Create Paper" : "Save Paper",
                    secondaryTitle: "Reset",
                    isSaveDisabled: !isPaperDraftValid(settings.settingsPaperDraft),
                    onSave: onSave,
                    onSecondary: {
                        settings.resetSettingsPaperDraft()
                    }
                )
            }
        }
    }
}

struct PrinterPaperSettingsSection: View {
    @ObservedObject var settings: SettingsCatalogModel
    let onSave: () -> Void

    private func printerName(for printerID: String) -> String {
        settings.printers.first(where: { $0.id == printerID })?.displayName ?? "Unknown Printer"
    }

    private func paperName(for paperID: String) -> String {
        settings.papers.first(where: { $0.id == paperID })?.displayName ?? "Unknown Paper"
    }

    var body: some View {
        settingsSection("Printer and paper settings") {
            VStack(alignment: .leading, spacing: 16) {
                if settings.printerPaperPresets.isEmpty {
                    settingsEmptyState("Save printer and paper settings here or inline from New Profile.")
                } else {
                    ForEach(settings.printerPaperPresets, id: \.id) { preset in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.displayName)
                                        .font(.headline)
                                    Text("\(printerName(for: preset.printerId)) / \(paperName(for: preset.paperId))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if !preset.printPath.isEmpty {
                                        Text(preset.printPath)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(preset.mediaSetting) / \(preset.qualityMode)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    if let limits = presetLimitsSummary(preset) {
                                        Text(limits)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button("Edit") {
                                    settings.editPrinterPaperPreset(preset)
                                }
                            }

                            if !preset.notes.isEmpty {
                                Text(preset.notes)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                PrinterPaperPresetEditorForm(
                    title: settings.settingsPresetDraft.title,
                    draft: $settings.settingsPresetDraft,
                    printers: settings.printers,
                    papers: settings.papers,
                    lockPrinterAndPaperSelection: false,
                    saveTitle: settings.settingsPresetDraft.id == nil ? "Create Settings" : "Save Settings",
                    secondaryTitle: "Reset",
                    isSaveDisabled: !settings.isSettingsPresetDraftValid,
                    onSave: onSave,
                    onSecondary: {
                        settings.resetSettingsPresetDraft()
                    }
                )
            }
        }
    }
}

struct DefaultsSettingsSection: View {
    var body: some View {
        settingsSection("Defaults") {
            Text("Application defaults stay separate from Printer, Paper, and Printer and Paper Settings records in v1.")
                .foregroundStyle(.secondary)
        }
    }
}

struct TechnicalSettingsSection: View {
    let appHealth: AppHealth?

    var body: some View {
        settingsSection("Technical") {
            VStack(alignment: .leading, spacing: 12) {
                if let appHealth {
                    OperationalDetailRow(title: "Readiness", value: appHealth.readiness.capitalized)

                    if !appHealth.blockingIssues.isEmpty {
                        settingsDetailList(title: "Blocking issues", items: appHealth.blockingIssues)
                    }

                    if !appHealth.warnings.isEmpty {
                        settingsDetailList(title: "Warnings", items: appHealth.warnings)
                    }
                }
            }
        }
    }
}

func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(.title2.weight(.semibold))
        content()
    }
}

func settingsDetailList(title: String, items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(AppTypography.detailLabel)
            .foregroundStyle(.secondary)
        ForEach(items, id: \.self) { item in
            Text(item)
                .font(AppTypography.detailValue)
        }
    }
}

func settingsEmptyState(_ message: String) -> some View {
    Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
}
