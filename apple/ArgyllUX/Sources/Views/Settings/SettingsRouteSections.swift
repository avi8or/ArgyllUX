import SwiftUI

struct SettingsSidebarView: View {
    @ObservedObject var settings: SettingsCatalogModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection("General") {
                    sidebarButton("Argyll", systemImage: "hammer", selection: .toolchain)
                    sidebarButton("Storage", systemImage: "internaldrive", selection: .storage)
                    sidebarButton("Defaults", systemImage: "slider.horizontal.3", selection: .defaults)
                }

                sidebarSection("Catalog") {
                    sidebarButton("Printers", systemImage: "printer", selection: .printers)
                    ForEach(settings.printers, id: \.id) { printer in
                        sidebarChildButton(printer.displayName, selection: .printer(printer.id))
                    }

                    sidebarButton("Papers", systemImage: "doc.text", selection: .papers)
                    ForEach(settings.papers, id: \.id) { paper in
                        sidebarChildButton(paper.displayName, selection: .paper(paper.id))
                    }

                    sidebarButton(
                        "Printer and Paper Settings",
                        systemImage: "slider.horizontal.below.rectangle",
                        selection: .printerPaperSettings
                    )
                    ForEach(settings.printerPaperPresets, id: \.id) { preset in
                        sidebarChildButton(preset.displayName, selection: .printerPaperSetting(preset.id))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.035))
    }

    private func sidebarSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
        }
    }

    private func sidebarButton(
        _ title: String,
        systemImage: String,
        selection: SettingsCatalogSelection
    ) -> some View {
        Button {
            settings.select(selection)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(sidebarButtonStyle(for: selection))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected(selection) ? .isSelected : [])
    }

    private func sidebarChildButton(
        _ title: String,
        selection: SettingsCatalogSelection
    ) -> some View {
        Button {
            settings.select(selection)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(isSelected(selection) ? Color.accentColor : Color.secondary.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 22)
        }
        .buttonStyle(sidebarButtonStyle(for: selection))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected(selection) ? .isSelected : [])
    }

    private func sidebarButtonStyle(for selection: SettingsCatalogSelection) -> SurfaceRowButtonStyle {
        SurfaceRowButtonStyle(
            isSelected: isSelected(selection),
            cornerRadius: 8,
            horizontalPadding: 10,
            verticalPadding: 8,
            minHeight: 38
        )
    }

    private func isSelected(_ selection: SettingsCatalogSelection) -> Bool {
        settings.selection == selection
    }
}

struct SettingsDetailPaneView: View {
    @ObservedObject var settings: SettingsCatalogModel
    let storagePaths: StoragePaths
    let appHealth: AppHealth?
    let onApplyToolchainPath: () -> Void
    let onRevalidateToolchain: () -> Void
    let onClearToolchainOverride: () -> Void
    let onStartNewProfile: (String?, String?) -> Void

    var body: some View {
        Group {
            switch settings.selection ?? .toolchain {
            case .toolchain:
                ToolchainSettingsDetailPane(
                    settings: settings,
                    appHealth: appHealth,
                    onApplyToolchainPath: onApplyToolchainPath,
                    onRevalidateToolchain: onRevalidateToolchain,
                    onClearToolchainOverride: onClearToolchainOverride
                )
            case .storage:
                StorageSettingsDetailPane(storagePaths: storagePaths)
            case .printers:
                SettingsCatalogLandingPane(
                    title: "Printers",
                    subtitle: settings.printers.isEmpty
                        ? "Create a printer once, then reuse it from New Profile and saved print-path settings."
                        : "Select a printer in the sidebar to inspect its capabilities or launch a new profile from it.",
                    records: settings.printers.map(\.displayName)
                )
            case .papers:
                SettingsCatalogLandingPane(
                    title: "Papers",
                    subtitle: settings.papers.isEmpty
                        ? "Create a paper record once, then reuse it from New Profile and saved print-path settings."
                        : "Select a paper in the sidebar to inspect its stock details or launch a new profile from it.",
                    records: settings.papers.map(\.displayName)
                )
            case .printerPaperSettings:
                SettingsCatalogLandingPane(
                    title: "Printer and Paper Settings",
                    subtitle: settings.printerPaperPresets.isEmpty
                        ? "Saved print-path settings attach media, quality, and limit assumptions to a printer and paper pair."
                        : "Select a saved settings record in the sidebar to inspect or edit its print-path assumptions.",
                    records: settings.printerPaperPresets.map(\.displayName)
                )
            case let .printer(id):
                if let printer = settings.printers.first(where: { $0.id == id }) {
                    PrinterDetailPane(
                        printer: printer,
                        onStartNewProfile: onStartNewProfile,
                        onEdit: {
                            settings.presentEditPrinterSheet(printer)
                        }
                    )
                } else {
                    SettingsMissingSelectionPane("This printer no longer exists.")
                }
            case let .paper(id):
                if let paper = settings.papers.first(where: { $0.id == id }) {
                    PaperDetailPane(
                        paper: paper,
                        onStartNewProfile: onStartNewProfile,
                        onEdit: {
                            settings.presentEditPaperSheet(paper)
                        }
                    )
                } else {
                    SettingsMissingSelectionPane("This paper no longer exists.")
                }
            case let .printerPaperSetting(id):
                if let preset = settings.printerPaperPresets.first(where: { $0.id == id }) {
                    PrinterPaperPresetDetailPane(
                        preset: preset,
                        printer: settings.printers.first(where: { $0.id == preset.printerId }),
                        paper: settings.papers.first(where: { $0.id == preset.paperId }),
                        onStartNewProfile: onStartNewProfile,
                        onEdit: {
                            settings.presentEditPresetSheet(preset)
                        }
                    )
                } else {
                    SettingsMissingSelectionPane("This saved print-path settings record no longer exists.")
                }
            case .defaults:
                DefaultsSettingsDetailPane()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ToolchainSettingsDetailPane: View {
    @ObservedObject var settings: SettingsCatalogModel
    let appHealth: AppHealth?
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
        SettingsDetailScaffold(
            title: "Argyll",
            subtitle: "Argyll status stays persistent in the footer, but Settings is where you correct the install path and inspect readiness details."
        ) {
            SettingsDetailCard("Status") {
                HStack(spacing: 10) {
                    StatusBadgeView(title: settings.argyllStatusLabel, tone: toolchainTone)
                    Text("ArgyllCMS \(settings.argyllVersionLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                OperationalDetailRow(title: "Detected path", value: settings.detectedToolchainPath)
                OperationalDetailRow(title: "Last validation", value: settings.lastValidationLabel)

                if let toolchainStatus = settings.toolchainStatus, !toolchainStatus.missingExecutables.isEmpty {
                    detailLine(title: "Missing tools", value: toolchainStatus.missingExecutables.joined(separator: ", "))
                }
            }

            SettingsDetailCard("Path Override") {
                HStack(spacing: 10) {
                    TextField("Argyll path", text: $settings.toolchainPathInput)
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

            if let appHealth {
                SettingsDetailCard("Readiness Details") {
                    detailLine(title: "App readiness", value: appHealth.readiness.capitalized)

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

private struct StorageSettingsDetailPane: View {
    let storagePaths: StoragePaths

    var body: some View {
        SettingsDetailScaffold(
            title: "Storage",
            subtitle: "These paths are diagnostic references for the app support surface, SQLite database, and logs."
        ) {
            SettingsDetailCard("Paths") {
                OperationalDetailRow(title: "App support path", value: storagePaths.appSupportPath)
                OperationalDetailRow(title: "Database path", value: storagePaths.databasePath)
                OperationalDetailRow(title: "Log path", value: storagePaths.logPath)
            }
        }
    }
}

private struct PrinterDetailPane: View {
    let printer: PrinterRecord
    let onStartNewProfile: (String?, String?) -> Void
    let onEdit: () -> Void

    var body: some View {
        SettingsDetailScaffold(
            title: printer.displayName,
            subtitle: structuredPrinterIdentity(printer)
        ) {
            SettingsDetailActions {
                Button("Use In New Profile") {
                    onStartNewProfile(printer.id, nil)
                }

                Button("Edit", action: onEdit)
            }

            SettingsDetailCard("Printer Capabilities") {
                detailLine(
                    title: "Colorant setup",
                    value: channelSetupSummary(printer.colorantFamily, printer.channelCount, printer.channelLabels)
                )

                if !printer.transportStyle.isEmpty {
                    detailLine(title: "Transport", value: printer.transportStyle)
                }

                if !printer.supportedMediaSettings.isEmpty {
                    detailLine(title: "Media settings", value: printer.supportedMediaSettings.joined(separator: ", "))
                }

                if !printer.supportedQualityModes.isEmpty {
                    detailLine(title: "Quality modes", value: printer.supportedQualityModes.joined(separator: ", "))
                }
            }

            if !printer.monochromePathNotes.isEmpty || !printer.notes.isEmpty {
                SettingsDetailCard("Notes") {
                    if !printer.monochromePathNotes.isEmpty {
                        detailLine(title: "Monochrome path notes", value: printer.monochromePathNotes)
                    }

                    if !printer.notes.isEmpty {
                        detailLine(title: "Notes", value: printer.notes)
                    }
                }
            }
        }
    }
}

private struct PaperDetailPane: View {
    let paper: PaperRecord
    let onStartNewProfile: (String?, String?) -> Void
    let onEdit: () -> Void

    var body: some View {
        SettingsDetailScaffold(
            title: paper.displayName,
            subtitle: structuredPaperIdentity(paper)
        ) {
            SettingsDetailActions {
                Button("Use In New Profile") {
                    onStartNewProfile(nil, paper.id)
                }

                Button("Edit", action: onEdit)
            }

            SettingsDetailCard("Paper Characteristics") {
                if let surfaceSummary = paperSurfaceSummary(paper) {
                    detailLine(title: "Surface", value: surfaceSummary)
                }

                if let specsSummary = paperSpecsSummary(paper) {
                    detailLine(title: "Stock", value: specsSummary)
                }

                if let detailsSummary = paperDetailsSummary(paper) {
                    detailLine(title: "Optical details", value: detailsSummary)
                }
            }

            if !paper.notes.isEmpty {
                SettingsDetailCard("Notes") {
                    detailLine(title: "Notes", value: paper.notes)
                }
            }
        }
    }
}

private struct PrinterPaperPresetDetailPane: View {
    let preset: PrinterPaperPresetRecord
    let printer: PrinterRecord?
    let paper: PaperRecord?
    let onStartNewProfile: (String?, String?) -> Void
    let onEdit: () -> Void

    var body: some View {
        SettingsDetailScaffold(
            title: preset.displayName,
            subtitle: "\(printer?.displayName ?? "Unknown Printer") / \(paper?.displayName ?? "Unknown Paper")"
        ) {
            SettingsDetailActions {
                Button("Use In New Profile") {
                    onStartNewProfile(preset.printerId, preset.paperId)
                }

                Button("Edit", action: onEdit)
            }

            SettingsDetailCard("Saved Print Path") {
                if !preset.printPath.isEmpty {
                    detailLine(title: "Print path", value: preset.printPath)
                }

                detailLine(title: "Media / quality", value: "\(preset.mediaSetting) / \(preset.qualityMode)")

                if let limits = presetLimitsSummary(preset) {
                    detailLine(title: "Limits", value: limits)
                }
            }

            if !preset.notes.isEmpty {
                SettingsDetailCard("Notes") {
                    detailLine(title: "Notes", value: preset.notes)
                }
            }
        }
    }
}

private struct DefaultsSettingsDetailPane: View {
    var body: some View {
        SettingsDetailScaffold(
            title: "Defaults",
            subtitle: "Defaults stay separate from printer, paper, and saved print-path records so the workflow context remains explicit."
        ) {
            SettingsDetailCard("Current Scope") {
                Text("The current slice keeps global defaults narrow. Printer, paper, and saved print-path settings stay as explicit records rather than being hidden behind one implicit default path.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsCatalogLandingPane: View {
    let title: String
    let subtitle: String
    let records: [String]

    var body: some View {
        SettingsDetailScaffold(title: title, subtitle: subtitle) {
            SettingsDetailCard(title) {
                if records.isEmpty {
                    Text("No saved records yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records, id: \.self) { record in
                        Text(record)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct SettingsMissingSelectionPane: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        SettingsDetailScaffold(title: "Selection Unavailable", subtitle: message) {
            SettingsDetailCard("State") {
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsDetailScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))

                Text(subtitle)
                    .foregroundStyle(.secondary)

                content()
            }
            .padding(24)
        }
    }
}

private struct SettingsDetailCard<Content: View>: View {
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

private struct SettingsDetailActions<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            content()
            Spacer()
        }
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
