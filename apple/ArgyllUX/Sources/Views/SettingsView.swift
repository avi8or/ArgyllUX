import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.largeTitle.weight(.semibold))

                settingsSection("Argyll") {
                    VStack(alignment: .leading, spacing: 14) {
                        detailRow(title: "Detected path", value: model.detectedToolchainPath)

                        HStack {
                            Text("Status")
                            Spacer()
                            StatusBadgeView(title: model.argyllStatusLabel, tone: toolchainTone)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Choose Path")
                                .font(.caption.weight(.semibold))
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
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(toolchainStatus.missingExecutables.joined(separator: ", "))
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                settingsSection("Storage") {
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow(title: "App support path", value: model.storagePaths.appSupportPath)
                        detailRow(title: "Database path", value: model.storagePaths.databasePath)
                        detailRow(title: "Log path", value: model.storagePaths.logPath)
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
                                            if !printer.transportStyle.isEmpty {
                                                Text(printer.transportStyle)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if !printer.supportedQualityModes.isEmpty {
                                                Text(printer.supportedQualityModes.joined(separator: ", "))
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
                            isSaveDisabled: model.settingsPrinterDraft.makeModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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
                                            if !paper.surfaceClass.isEmpty {
                                                Text(paper.surfaceClass)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if !paper.weightThickness.isEmpty {
                                                Text(paper.weightThickness)
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
                            isSaveDisabled: model.settingsPaperDraft.vendorProductName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            onSave: {
                                Task { await model.saveSettingsPaper() }
                            },
                            onSecondary: {
                                model.resetSettingsPaperDraft()
                            }
                        )
                    }
                }

                settingsSection("Defaults") {
                    Text("Application defaults stay separate from Printer and Paper records in v1.")
                        .foregroundStyle(.secondary)
                }

                settingsSection("Technical") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let appHealth = model.appHealth {
                            detailRow(title: "Readiness", value: appHealth.readiness.capitalized)

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

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            content()
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    private func detailList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline)
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

            TextField("Make / model", text: $draft.makeModel)
                .textFieldStyle(.roundedBorder)

            TextField("Nickname", text: $draft.nickname)
                .textFieldStyle(.roundedBorder)

            TextField("Transport style", text: $draft.transportStyle)
                .textFieldStyle(.roundedBorder)

            TextField("Supported quality modes", text: $draft.supportedQualityModesText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            TextField("Monochrome path notes", text: $draft.monochromePathNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

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

            TextField("Vendor / product name", text: $draft.vendorProductName)
                .textFieldStyle(.roundedBorder)

            TextField("Surface class", text: $draft.surfaceClass)
                .textFieldStyle(.roundedBorder)

            TextField("Weight / thickness", text: $draft.weightThickness)
                .textFieldStyle(.roundedBorder)

            TextField("OBA / fluorescence notes", text: $draft.obaFluorescenceNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

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
