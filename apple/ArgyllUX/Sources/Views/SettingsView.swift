import SwiftUI

private let paperWeightUnits: [PaperWeightUnit] = [.unspecified, .gsm, .lb]
private let paperThicknessUnits: [PaperThicknessUnit] = [.unspecified, .mil, .mm, .micron]

struct CatalogEntryDraft: Equatable {
    var pendingValue = ""

    @discardableResult
    mutating func commit(into values: inout [String]) -> Bool {
        let trimmedValue = pendingValue.trimmed
        guard !trimmedValue.isEmpty else { return false }
        values.append(trimmedValue)
        pendingValue = ""
        return true
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.largeTitle.weight(.semibold))

                settingsSection("Argyll") {
                    VStack(alignment: .leading, spacing: 14) {
                        OperationalDetailRow(title: "Detected path", value: model.detectedToolchainPath)

                        HStack {
                            Text("Status")
                            Spacer()
                            StatusBadgeView(title: model.argyllStatusLabel, tone: toolchainTone)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Choose Path")
                                .font(AppTypography.detailLabel)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                TextField("Choose Path", text: $model.toolchainPathInput)
                                    .textFieldStyle(.roundedBorder)

                                Button("Choose Path") {
                                    if let selectedPath = PathSelection.chooseDirectory(initialPath: model.toolchainPathInput) {
                                        model.toolchainPathInput = selectedPath
                                    }
                                }
                            }

                            HStack(spacing: 10) {
                                Button("Apply Path") {
                                    Task { await model.applyToolchainPath() }
                                }

                                Button("Re-run Validation") {
                                    Task { await model.revalidateToolchain() }
                                }

                                Button("Clear Override") {
                                    Task { await model.clearToolchainOverride() }
                                }
                                .disabled(model.toolchainPathInput.isEmpty)
                            }
                        }

                        if let toolchainStatus = model.toolchainStatus, !toolchainStatus.missingExecutables.isEmpty {
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

                settingsSection("Storage") {
                    VStack(alignment: .leading, spacing: 12) {
                        OperationalDetailRow(title: "App support path", value: model.storagePaths.appSupportPath)
                        OperationalDetailRow(title: "Database path", value: model.storagePaths.databasePath)
                        OperationalDetailRow(title: "Log path", value: model.storagePaths.logPath)
                    }
                }

                settingsSection("Printers") {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.printers.isEmpty {
                            emptyState("Create a printer here or inline from New Profile.")
                        } else {
                            ForEach(model.printers, id: \.id) { printer in
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
                                                model.startNewProfileFromSettings(printerId: printer.id)
                                            }

                                            Button("Edit") {
                                                model.editPrinter(printer)
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
                            title: model.settingsPrinterDraft.title,
                            draft: $model.settingsPrinterDraft,
                            saveTitle: model.settingsPrinterDraft.id == nil ? "Create Printer" : "Save Printer",
                            secondaryTitle: "Reset",
                            isSaveDisabled: !isPrinterDraftValid(model.settingsPrinterDraft),
                            onSave: {
                                Task { await model.saveSettingsPrinter() }
                            },
                            onSecondary: {
                                model.resetSettingsPrinterDraft()
                            }
                        )
                    }
                }

                settingsSection("Papers") {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.papers.isEmpty {
                            emptyState("Create a paper here or inline from New Profile.")
                        } else {
                            ForEach(model.papers, id: \.id) { paper in
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
                                                model.startNewProfileFromSettings(paperId: paper.id)
                                            }

                                            Button("Edit") {
                                                model.editPaper(paper)
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
                            title: model.settingsPaperDraft.title,
                            draft: $model.settingsPaperDraft,
                            saveTitle: model.settingsPaperDraft.id == nil ? "Create Paper" : "Save Paper",
                            secondaryTitle: "Reset",
                            isSaveDisabled: !isPaperDraftValid(model.settingsPaperDraft),
                            onSave: {
                                Task { await model.saveSettingsPaper() }
                            },
                            onSecondary: {
                                model.resetSettingsPaperDraft()
                            }
                        )
                    }
                }

                settingsSection("Printer and paper settings") {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.printerPaperPresets.isEmpty {
                            emptyState("Save printer and paper settings here or inline from New Profile.")
                        } else {
                            ForEach(model.printerPaperPresets, id: \.id) { preset in
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
                                            model.editPrinterPaperPreset(preset)
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
                            title: model.settingsPresetDraft.title,
                            draft: $model.settingsPresetDraft,
                            printers: model.printers,
                            papers: model.papers,
                            lockPrinterAndPaperSelection: false,
                            saveTitle: model.settingsPresetDraft.id == nil ? "Create Settings" : "Save Settings",
                            secondaryTitle: "Reset",
                            isSaveDisabled: !model.isSettingsPresetDraftValid,
                            onSave: {
                                Task { await model.saveSettingsPreset() }
                            },
                            onSecondary: {
                                model.resetSettingsPresetDraft()
                            }
                        )
                    }
                }

                settingsSection("Defaults") {
                    Text("Application defaults stay separate from Printer, Paper, and Printer and Paper Settings records in v1.")
                        .foregroundStyle(.secondary)
                }

                settingsSection("Technical") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let appHealth = model.appHealth {
                            OperationalDetailRow(title: "Readiness", value: appHealth.readiness.capitalized)

                            if !appHealth.blockingIssues.isEmpty {
                                detailList(title: "Blocking issues", items: appHealth.blockingIssues)
                            }

                            if !appHealth.warnings.isEmpty {
                                detailList(title: "Warnings", items: appHealth.warnings)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var toolchainTone: StatusBadgeView.Tone {
        switch model.toolchainStatus?.state {
        case .ready:
            .ready
        case .partial:
            .attention
        case .notFound, .none:
            .blocked
        }
    }

    private func printerName(for printerID: String) -> String {
        model.printers.first(where: { $0.id == printerID })?.displayName ?? "Unknown Printer"
    }

    private func paperName(for paperID: String) -> String {
        model.papers.first(where: { $0.id == paperID })?.displayName ?? "Unknown Paper"
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            content()
        }
    }

    private func detailList(title: String, items: [String]) -> some View {
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

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PrinterEditorForm: View {
    let title: String
    @Binding var draft: PrinterDraft
    let saveTitle: String
    let secondaryTitle: String
    let isSaveDisabled: Bool
    let onSave: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            HStack(spacing: 12) {
                TextField("Manufacturer", text: $draft.manufacturer)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $draft.model)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Nickname", text: $draft.nickname)
                .textFieldStyle(.roundedBorder)

            TextField("Transport style", text: $draft.transportStyle)
                .textFieldStyle(.roundedBorder)

            Picker("Argyll profiling setup", selection: $draft.colorantFamily) {
                ForEach(ColorantFamily.structuredCases, id: \.self) { family in
                    Text(family.displayLabel).tag(family)
                }
            }

            if draft.colorantFamily == .extendedN {
                Picker("Channel count", selection: $draft.channelCount) {
                    ForEach(6 ... 15, id: \.self) { count in
                        Text("\(count) channels").tag(UInt32(count))
                    }
                }

                CatalogListEditor(
                    title: "Channel labels",
                    helperText: "Optional labels for display and future calibration controls.",
                    addPrompt: "Add channel label",
                    values: $draft.channelLabels
                )
            }

            CatalogListEditor(
                title: "Media settings",
                helperText: "These options become the allowed preset choices for this printer.",
                addPrompt: "Add media setting",
                values: $draft.supportedMediaSettings
            )

            CatalogListEditor(
                title: "Quality modes",
                helperText: "These options become the allowed preset choices for this printer.",
                addPrompt: "Add quality mode",
                values: $draft.supportedQualityModes
            )

            TextField("Monochrome path notes", text: $draft.monochromePathNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 4)

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 4)

            HStack(spacing: 10) {
                Button(saveTitle, action: onSave)
                    .disabled(isSaveDisabled)

                Button(secondaryTitle, action: onSecondary)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PaperEditorForm: View {
    let title: String
    @Binding var draft: PaperDraft
    let saveTitle: String
    let secondaryTitle: String
    let isSaveDisabled: Bool
    let onSave: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            HStack(spacing: 12) {
                TextField("Manufacturer", text: $draft.manufacturer)
                    .textFieldStyle(.roundedBorder)
                TextField("Paper line / make", text: $draft.paperLine)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Surface class", selection: $draft.surfaceClassSelection) {
                Text("Select Surface Class").tag("")
                ForEach(curatedPaperSurfaceClasses, id: \.self) { surfaceClass in
                    Text(surfaceClass).tag(surfaceClass)
                }
                Text("Other").tag("Other")
            }

            if draft.surfaceClassSelection == "Other" {
                TextField("Other surface class", text: $draft.surfaceClassOther)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Surface texture", text: $draft.surfaceTexture)
                .textFieldStyle(.roundedBorder)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Basis weight", text: $draft.basisWeightValue)
                        .textFieldStyle(.roundedBorder)

                    Picker("Weight unit", selection: $draft.basisWeightUnit) {
                        ForEach(paperWeightUnits, id: \.self) { unit in
                            Text(unit.pickerLabel).tag(unit)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Thickness", text: $draft.thicknessValue)
                        .textFieldStyle(.roundedBorder)

                    Picker("Thickness unit", selection: $draft.thicknessUnit) {
                        ForEach(paperThicknessUnits, id: \.self) { unit in
                            Text(unit.pickerLabel).tag(unit)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                TextField("Base material", text: $draft.baseMaterial)
                    .textFieldStyle(.roundedBorder)
                TextField("Media color", text: $draft.mediaColor)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                TextField("Opacity", text: $draft.opacity)
                    .textFieldStyle(.roundedBorder)
                TextField("Whiteness", text: $draft.whiteness)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("OBA content", text: $draft.obaContent)
                .textFieldStyle(.roundedBorder)

            TextField("Ink compatibility", text: $draft.inkCompatibility)
                .textFieldStyle(.roundedBorder)

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 4)

            HStack(spacing: 10) {
                Button(saveTitle, action: onSave)
                    .disabled(isSaveDisabled)

                Button(secondaryTitle, action: onSecondary)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PrinterPaperPresetEditorForm: View {
    let title: String
    @Binding var draft: PrinterPaperPresetDraft
    let printers: [PrinterRecord]
    let papers: [PaperRecord]
    let lockPrinterAndPaperSelection: Bool
    let saveTitle: String
    let secondaryTitle: String
    let isSaveDisabled: Bool
    let onSave: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        let selectedPrinter = printers.first(where: { $0.id == draft.printerId })
        let selectedPaper = papers.first(where: { $0.id == draft.paperId })
        let availableMediaSettings = selectedPrinter?.supportedMediaSettings ?? []
        let availableQualityModes = selectedPrinter?.supportedQualityModes ?? []
        let selectedPrinterHasBlackChannel = selectedPrinter?.colorantFamily.hasBlackChannel(channelLabels: selectedPrinter?.channelLabels ?? []) ?? false

        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if lockPrinterAndPaperSelection {
                lockedSelectionSummary(
                    title: "Printer",
                    primary: selectedPrinter?.displayName ?? "Not selected",
                    secondary: selectedPrinter.map(structuredPrinterIdentity)
                )

                lockedSelectionSummary(
                    title: "Paper",
                    primary: selectedPaper?.displayName ?? "Not selected",
                    secondary: selectedPaper.map(structuredPaperIdentity)
                )
            } else {
                Picker(
                    "Printer",
                    selection: Binding(
                        get: { draft.printerId ?? "" },
                        set: { selection in
                            draft.printerId = selection.isEmpty ? nil : selection
                            sanitizePresetDraftForSelectedPrinter()
                        }
                    )
                ) {
                    Text("Select Printer").tag("")
                    ForEach(printers, id: \.id) { printer in
                        Text(printer.displayName).tag(printer.id)
                    }
                }

                Picker(
                    "Paper",
                    selection: Binding(
                        get: { draft.paperId ?? "" },
                        set: { selection in
                            draft.paperId = selection.isEmpty ? nil : selection
                        }
                    )
                ) {
                    Text("Select Paper").tag("")
                    ForEach(papers, id: \.id) { paper in
                        Text(paper.displayName).tag(paper.id)
                    }
                }
            }

            TextField("Label", text: $draft.label)
                .textFieldStyle(.roundedBorder)

            TextField("Print path", text: $draft.printPath)
                .textFieldStyle(.roundedBorder)

            Text("Use this to distinguish Mirage, Photoshop -> Canon driver, or another route that prints the target.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let selectedPrinter {
                Text(channelSetupSummary(selectedPrinter.colorantFamily, selectedPrinter.channelCount, selectedPrinter.channelLabels))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if availableMediaSettings.isEmpty || availableQualityModes.isEmpty {
                Text("Add media settings and quality modes on the selected printer before saving printer and paper settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Media setting", selection: $draft.mediaSetting) {
                    Text("Select Media Setting").tag("")
                    ForEach(availableMediaSettings, id: \.self) { mediaSetting in
                        Text(mediaSetting).tag(mediaSetting)
                    }
                }

                Picker("Quality mode", selection: $draft.qualityMode) {
                    Text("Select Quality Mode").tag("")
                    ForEach(availableQualityModes, id: \.self) { qualityMode in
                        Text(qualityMode).tag(qualityMode)
                    }
                }

                Text("The wrong media setting cannot be fixed by profiling.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let selectedPaper {
                Text(structuredPaperIdentity(selectedPaper))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                TextField("Total ink limit %", text: $draft.totalInkLimitPercentText)
                    .textFieldStyle(.roundedBorder)

                if selectedPrinterHasBlackChannel {
                    TextField("Black ink limit %", text: $draft.blackInkLimitPercentText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("Advanced limits affect command generation and should match the real print path.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 4)

            HStack(spacing: 10) {
                Button(saveTitle, action: onSave)
                    .disabled(isSaveDisabled)

                Button(secondaryTitle, action: onSecondary)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            sanitizePresetDraftForSelectedPrinter()
        }
    }

    private func lockedSelectionSummary(title: String, primary: String, secondary: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppTypography.detailLabel)
                .foregroundStyle(.secondary)
            Text(primary)
                .font(.subheadline)
            if let secondary, !secondary.isEmpty {
                Text(secondary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sanitizePresetDraftForSelectedPrinter() {
        sanitizePrinterPaperPresetDraft(&draft, printers: printers)
    }
}

struct CatalogListEditor: View {
    let title: String
    let helperText: String?
    let addPrompt: String
    @Binding var values: [String]
    @State private var draft = CatalogEntryDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.detailLabel)
                .foregroundStyle(.secondary)

            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if values.isEmpty {
                Text("No saved entries yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                HStack(spacing: 10) {
                    TextField(title, text: Binding(
                        get: { values[index] },
                        set: { values[index] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button("Remove") {
                        values.remove(at: index)
                    }
                }
            }

            HStack(spacing: 10) {
                TextField(addPrompt, text: $draft.pendingValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitPendingValue)

                Button(action: commitPendingValue) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(title)")
            }
        }
    }

    private func commitPendingValue() {
        draft.commit(into: &values)
    }
}

private func isPrinterDraftValid(_ draft: PrinterDraft) -> Bool {
    !draft.manufacturer.trimmed.isEmpty &&
        !draft.model.trimmed.isEmpty &&
        (draft.colorantFamily != .extendedN || (6 ... 15).contains(draft.channelCount))
}

private func isPaperDraftValid(_ draft: PaperDraft) -> Bool {
    !draft.paperLine.trimmed.isEmpty &&
        (draft.surfaceClassSelection != "Other" || !draft.surfaceClassOther.trimmed.isEmpty)
}

private func structuredPrinterIdentity(_ printer: PrinterRecord) -> String {
    let manufacturer = printer.manufacturer.trimmed
    let model = printer.model.trimmed
    let base = [manufacturer, model].filter { !$0.isEmpty }.joined(separator: " ")
    if printer.nickname.trimmed.isEmpty {
        return base
    }
    return "\(base) • \(printer.nickname)"
}

private func structuredPaperIdentity(_ paper: PaperRecord) -> String {
    [paper.manufacturer.trimmed, paper.paperLine.trimmed]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

private func paperSurfaceSummary(_ paper: PaperRecord) -> String? {
    let parts = [paper.surfaceClass.trimmed, paper.surfaceTexture.trimmed].filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

private func paperSpecsSummary(_ paper: PaperRecord) -> String? {
    let parts = [
        paperMeasurementSummary(value: paper.basisWeightValue, unitLabel: paper.basisWeightUnit.summaryLabel),
        paperMeasurementSummary(value: paper.thicknessValue, unitLabel: paper.thicknessUnit.summaryLabel),
    ].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

private func paperDetailsSummary(_ paper: PaperRecord) -> String? {
    let parts = [
        paper.baseMaterial.trimmed,
        paper.mediaColor.trimmed,
        paper.opacity.trimmed.isEmpty ? "" : "Opacity \(paper.opacity.trimmed)",
        paper.whiteness.trimmed.isEmpty ? "" : "Whiteness \(paper.whiteness.trimmed)",
        paper.obaContent.trimmed.isEmpty ? "" : "OBA \(paper.obaContent.trimmed)",
        paper.inkCompatibility.trimmed,
    ].filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

private func paperMeasurementSummary(value: String, unitLabel: String?) -> String? {
    let trimmedValue = value.trimmed
    guard !trimmedValue.isEmpty else { return nil }
    guard let unitLabel, !unitLabel.isEmpty else { return trimmedValue }
    return "\(trimmedValue) \(unitLabel)"
}

func channelSetupSummary(_ family: ColorantFamily, _ channelCount: UInt32, _ channelLabels: [String]) -> String {
    var parts = [family.displayLabel]
    if family == .extendedN {
        parts.append("\(channelCount) channels")
        if !channelLabels.isEmpty {
            parts.append(channelLabels.joined(separator: ", "))
        }
    }
    return parts.joined(separator: " • ")
}

private func presetLimitsSummary(_ preset: PrinterPaperPresetRecord) -> String? {
    var parts: [String] = []
    if let totalInkLimitPercent = preset.totalInkLimitPercent {
        parts.append("TAC \(totalInkLimitPercent)%")
    }
    if let blackInkLimitPercent = preset.blackInkLimitPercent {
        parts.append("Black \(blackInkLimitPercent)%")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

private func detailLine(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(AppTypography.detailLabel)
            .foregroundStyle(.secondary)
        Text(value)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension PaperWeightUnit {
    var pickerLabel: String {
        switch self {
        case .unspecified:
            "Unit"
        case .gsm:
            "gsm"
        case .lb:
            "lb"
        }
    }

    var summaryLabel: String? {
        switch self {
        case .unspecified:
            nil
        case .gsm:
            "gsm"
        case .lb:
            "lb"
        }
    }
}

private extension PaperThicknessUnit {
    var pickerLabel: String {
        switch self {
        case .unspecified:
            "Unit"
        case .mil:
            "mil"
        case .mm:
            "mm"
        case .micron:
            "micron"
        }
    }

    var summaryLabel: String? {
        switch self {
        case .unspecified:
            nil
        case .mil:
            "mil"
        case .mm:
            "mm"
        case .micron:
            "micron"
        }
    }
}
