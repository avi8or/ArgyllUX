import SwiftUI

// Shared modal editor forms for Settings catalog records and New Profile context creation.
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

struct PrinterEditorForm: View {
    let title: String
    @Binding var draft: PrinterDraft
    let saveTitle: String
    let secondaryTitle: String
    let isSaveDisabled: Bool
    let onSave: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        SettingsEditorScaffold(
            title: title,
            saveTitle: saveTitle,
            secondaryTitle: secondaryTitle,
            isSaveDisabled: isSaveDisabled,
            onSave: onSave,
            onSecondary: onSecondary
        ) {
            SettingsEditorSection("Identity") {
                SettingsEditorColumns {
                    TextField("Manufacturer", text: $draft.manufacturer)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $draft.model)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsEditorColumns {
                    TextField("Nickname", text: $draft.nickname)
                        .textFieldStyle(.roundedBorder)
                    TextField("Transport style", text: $draft.transportStyle)
                        .textFieldStyle(.roundedBorder)
                }
            }

            SettingsEditorSection("Ink And Channel Setup") {
                Picker("Argyll profiling setup", selection: colorantFamilyBinding) {
                    ForEach(ColorantFamily.structuredCases, id: \.self) { family in
                        Text(family.displayLabel).tag(family)
                    }
                }
                .pickerStyle(.menu)

                if draft.colorantFamily == .extendedN {
                    ChannelCountPicker(channelCount: $draft.channelCount)

                    CatalogListEditor(
                        title: "Channel labels",
                        helperText: "Optional labels for display and future calibration controls.",
                        addPrompt: "Add channel label",
                        values: $draft.channelLabels
                    )
                }
            }

            SettingsEditorSection("Driver Options") {
                CatalogListEditor(
                    title: "Media settings",
                    helperText: "These values become the allowed media setting choices for this printer.",
                    addPrompt: "Add media setting",
                    values: $draft.supportedMediaSettings
                )

                CatalogListEditor(
                    title: "Quality modes",
                    helperText: "These values become the allowed quality mode choices for this printer.",
                    addPrompt: "Add quality mode",
                    values: $draft.supportedQualityModes
                )
            }

            SettingsEditorSection("Notes") {
                TextField("Monochrome path notes", text: $draft.monochromePathNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2 ... 4)

                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 6)
            }
        }
    }

    private var colorantFamilyBinding: Binding<ColorantFamily> {
        Binding(
            get: { draft.colorantFamily },
            set: { family in
                draft.colorantFamily = family
                if family == .extendedN {
                    draft.channelCount = containedExtendedChannelCount(draft.channelCount)
                }
            }
        )
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
        SettingsEditorScaffold(
            title: title,
            saveTitle: saveTitle,
            secondaryTitle: secondaryTitle,
            isSaveDisabled: isSaveDisabled,
            onSave: onSave,
            onSecondary: onSecondary
        ) {
            SettingsEditorSection("Identity") {
                SettingsEditorColumns {
                    TextField("Manufacturer", text: $draft.manufacturer)
                        .textFieldStyle(.roundedBorder)
                    TextField("Paper line / make", text: $draft.paperLine)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsEditorColumns {
                    Picker("Surface class", selection: $draft.surfaceClassSelection) {
                        Text("Select Surface Class").tag("")
                        ForEach(curatedPaperSurfaceClasses, id: \.self) { surfaceClass in
                            Text(surfaceClass).tag(surfaceClass)
                        }
                        Text("Other").tag("Other")
                    }
                    .pickerStyle(.menu)

                    TextField("Surface texture", text: $draft.surfaceTexture)
                        .textFieldStyle(.roundedBorder)
                }

                if draft.surfaceClassSelection == "Other" {
                    TextField("Other surface class", text: $draft.surfaceClassOther)
                        .textFieldStyle(.roundedBorder)
                }
            }

            SettingsEditorSection("Paper Stock") {
                SettingsEditorColumns {
                    SettingsEditorColumns {
                        TextField("Basis weight", text: $draft.basisWeightValue)
                            .textFieldStyle(.roundedBorder)
                        Picker("Weight unit", selection: $draft.basisWeightUnit) {
                            ForEach(paperWeightUnits, id: \.self) { unit in
                                Text(unit.pickerLabel).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsEditorColumns {
                        TextField("Thickness", text: $draft.thicknessValue)
                            .textFieldStyle(.roundedBorder)
                        Picker("Thickness unit", selection: $draft.thicknessUnit) {
                            ForEach(paperThicknessUnits, id: \.self) { unit in
                                Text(unit.pickerLabel).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                SettingsEditorColumns {
                    TextField("Base material", text: $draft.baseMaterial)
                        .textFieldStyle(.roundedBorder)
                    TextField("Media color", text: $draft.mediaColor)
                        .textFieldStyle(.roundedBorder)
                }
            }

            SettingsEditorSection("Optical Properties") {
                SettingsEditorColumns {
                    TextField("Opacity", text: $draft.opacity)
                        .textFieldStyle(.roundedBorder)
                    TextField("Whiteness", text: $draft.whiteness)
                        .textFieldStyle(.roundedBorder)
                }

                SettingsEditorColumns {
                    TextField("OBA content", text: $draft.obaContent)
                        .textFieldStyle(.roundedBorder)
                    TextField("Ink compatibility", text: $draft.inkCompatibility)
                        .textFieldStyle(.roundedBorder)
                }
            }

            SettingsEditorSection("Notes") {
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 6)
            }
        }
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
        let selectedPrinterHasBlackChannel = selectedPrinter?.colorantFamily.hasBlackChannel(
            channelLabels: selectedPrinter?.channelLabels ?? []
        ) ?? false

        SettingsEditorScaffold(
            title: title,
            saveTitle: saveTitle,
            secondaryTitle: secondaryTitle,
            isSaveDisabled: isSaveDisabled,
            onSave: onSave,
            onSecondary: onSecondary
        ) {
            SettingsEditorSection("Pair Selection") {
                if lockPrinterAndPaperSelection {
                    SettingsEditorColumns {
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
                    }
                } else {
                    SettingsEditorColumns {
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
                        .pickerStyle(.menu)

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
                        .pickerStyle(.menu)
                    }
                }
            }

            SettingsEditorSection("Identity") {
                SettingsEditorColumns {
                    TextField("Label", text: $draft.label)
                        .textFieldStyle(.roundedBorder)
                    TextField("Print path", text: $draft.printPath)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Use this to distinguish Mirage, Photoshop -> Canon driver, or another route that prints the target.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            SettingsEditorSection("Driver Settings") {
                if let selectedPrinter {
                    Text(channelSetupSummary(selectedPrinter.colorantFamily, selectedPrinter.channelCount, selectedPrinter.channelLabels))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let selectedPaper {
                    Text(structuredPaperIdentity(selectedPaper))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if availableMediaSettings.isEmpty || availableQualityModes.isEmpty {
                    Text("Add media settings and quality modes on the selected printer before saving printer and paper settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    SettingsEditorColumns {
                        Picker("Media setting", selection: $draft.mediaSetting) {
                            Text("Select Media Setting").tag("")
                            ForEach(availableMediaSettings, id: \.self) { mediaSetting in
                                Text(mediaSetting).tag(mediaSetting)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Quality mode", selection: $draft.qualityMode) {
                            Text("Select Quality Mode").tag("")
                            ForEach(availableQualityModes, id: \.self) { qualityMode in
                                Text(qualityMode).tag(qualityMode)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Text("The wrong media setting cannot be fixed by profiling.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsEditorSection("Advanced Limits") {
                SettingsEditorColumns {
                    TextField("Total ink limit %", text: $draft.totalInkLimitPercentText)
                        .textFieldStyle(.roundedBorder)

                    if selectedPrinterHasBlackChannel {
                        TextField("Black ink limit %", text: $draft.blackInkLimitPercentText)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        EmptyView()
                    }
                }

                Text("Advanced limits affect command generation and should match the real print path.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 6)
            }
        }
        .onAppear {
            sanitizePresetDraftForSelectedPrinter()
        }
    }

    private func lockedSelectionSummary(title: String, primary: String, secondary: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sanitizePresetDraftForSelectedPrinter() {
        sanitizePrinterPaperPresetDraft(&draft, printers: printers)
    }
}

private struct SettingsEditorScaffold<Content: View>: View {
    let title: String
    let saveTitle: String
    let secondaryTitle: String
    let isSaveDisabled: Bool
    let onSave: () -> Void
    let onSecondary: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.title2.weight(.semibold))

                content()

                HStack(spacing: 10) {
                    Spacer()

                    Button(secondaryTitle, action: onSecondary)

                    Button(saveTitle, action: onSave)
                        .disabled(isSaveDisabled)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 700, minHeight: 520)
        .frame(idealWidth: 760, maxWidth: 820, idealHeight: 680, maxHeight: 760)
    }
}

private struct SettingsEditorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SettingsEditorColumns<Content: View>: View {
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                content()
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChannelCountPicker: View {
    @Binding var channelCount: UInt32

    private let counts = Array(UInt32(6) ... UInt32(15))

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Channel count")
                .font(AppTypography.detailLabel)
                .foregroundStyle(.secondary)

            Picker("Channel count", selection: $channelCount) {
                ForEach(counts, id: \.self) { count in
                    Text("\(count) channels").tag(count)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 220, alignment: .leading)

            Text("Use Extended N-color only when the printer has more than the fixed Gray, RGB, CMY, or CMYK channel sets.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            channelCount = containedExtendedChannelCount(channelCount)
        }
    }
}

private func containedExtendedChannelCount(_ count: UInt32) -> UInt32 {
    min(max(count, 6), 15)
}

struct CatalogListEditor: View {
    let title: String
    let helperText: String?
    let addPrompt: String
    @Binding var values: [String]
    @State private var draft = CatalogEntryDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            ForEach(Array(values.enumerated()), id: \.offset) { index, _ in
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
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }

    private func commitPendingValue() {
        draft.commit(into: &values)
    }
}

func detailLine(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(AppTypography.detailLabel)
            .foregroundStyle(.secondary)
        Text(value)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
