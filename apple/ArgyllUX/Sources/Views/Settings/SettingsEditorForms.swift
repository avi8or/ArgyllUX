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
        let selectedPrinterHasBlackChannel = selectedPrinter?.colorantFamily.hasBlackChannel(
            channelLabels: selectedPrinter?.channelLabels ?? []
        ) ?? false

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
