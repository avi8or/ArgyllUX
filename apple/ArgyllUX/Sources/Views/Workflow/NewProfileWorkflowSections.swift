import SwiftUI

private let measurementModes: [MeasurementMode] = [.strip, .patch, .scanFile]

struct NewProfileWorkflowHeaderView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("New Profile")
                            .font(.title2.weight(.semibold))

                        StatusBadgeView(title: workflowStageTitle(workflow.effectiveWorkflowStage), tone: stageTone(for: detail))

                        Text(detail.status)
                            .font(AppTypography.shellUtility)
                            .foregroundStyle(.secondary)

                        if detail.isCommandRunning {
                            ProgressView()
                                .controlSize(.small)
                                .help("Command running")
                                .accessibilityLabel("Command running")
                        }
                    }

                    Text(commandSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                NewProfilePrimaryActionButton(
                    presentation: workflow.workflowPrimaryActionPresentation,
                    action: actions.performPrimaryAction
                )

                NewProfileSecondaryActionsMenu(
                    workflow: workflow,
                    detail: detail,
                    actions: actions
                )
            }

            WorkflowProgressRibbon(items: workflowProgressItems(for: detail))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var commandSubtitle: String {
        let presentation = workflow.workflowPrimaryActionPresentation

        if let disabledReason = presentation.disabledReason {
            return disabledReason
        }

        return "\(detail.title) - Next: \(presentation.title)"
    }

    private func stageTone(for detail: NewProfileJobDetail) -> StatusBadgeView.Tone {
        switch detail.stage {
        case .completed:
            .ready
        case .blocked, .failed:
            .blocked
        case .review, .publish, .target, .print, .drying, .measure, .build, .context:
            .attention
        }
    }
}

private struct NewProfilePrimaryActionButton: View {
    let presentation: WorkflowPrimaryActionPresentation
    let action: () -> Void

    var body: some View {
        Button(presentation.title, action: action)
            .disabled(!presentation.isEnabled)
            .buttonStyle(.borderedProminent)
            .help(presentation.disabledReason ?? presentation.title)
            .accessibilityHint(presentation.disabledReason ?? "Runs the next step for this New Profile job.")
    }
}

private struct NewProfileSecondaryActionsMenu: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        Menu {
            Button("Open Output Folder") {
                workflow.revealPathInFinder(detail.workspacePath)
            }

            Button("Open CLI Transcript") {
                actions.openCliTranscript(detail.id)
            }

            if let deletionTitle = workflow.currentWorkflowDeletionActionTitle {
                Divider()
                Button(deletionTitle, role: .destructive, action: actions.requestWorkflowDeletion)
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .help("Job actions")
    }
}

private struct WorkflowProgressRibbon: View {
    let items: [WorkflowProgressItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullProgressRow
            compactProgressSummary
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var fullProgressRow: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                WorkflowProgressPill(item: item)
            }
        }
    }

    private var compactProgressSummary: some View {
        HStack(spacing: 8) {
            if let currentItem {
                WorkflowCompactProgressPill(item: currentItem)
            }

            Text("\(completedCount)/\(items.count) done")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var currentItem: WorkflowProgressItem? {
        items.first { $0.state == .current }
            ?? items.first { $0.state == .blocked }
            ?? items.last { $0.state == .completed }
            ?? items.first
    }

    private var completedCount: Int {
        items.filter { $0.state == .completed }.count
    }
}

private struct WorkflowProgressPill: View {
    let item: WorkflowProgressItem

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(progressColor)
                .frame(width: 7, height: 7)

            Text(item.title)
                .font(.caption.weight(item.state == .current ? .semibold : .regular))
                .lineLimit(1)

            Text(item.status)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(progressBackground, in: Capsule())
        .accessibilityLabel("\(item.title). \(item.status).")
    }

    private var progressColor: Color {
        stageSummaryColor(item.state)
    }

    private var progressBackground: Color {
        switch item.state {
        case .current:
            Color.accentColor.opacity(0.12)
        case .blocked:
            Color.red.opacity(0.10)
        case .completed, .upcoming:
            Color.secondary.opacity(0.06)
        }
    }
}

private struct WorkflowCompactProgressPill: View {
    let item: WorkflowProgressItem

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stageSummaryColor(item.state))
                .frame(width: 7, height: 7)

            Text("\(item.title): \(item.status)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(compactBackground, in: Capsule())
        .accessibilityLabel("\(item.title). \(item.status).")
    }

    private var compactBackground: Color {
        switch item.state {
        case .current:
            Color.accentColor.opacity(0.12)
        case .blocked:
            Color.red.opacity(0.10)
        case .completed, .upcoming:
            Color.secondary.opacity(0.06)
        }
    }
}

struct NewProfileJobContextRail: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            jobContextHeader

            workflowSection("Job Context") {
                VStack(alignment: .leading, spacing: 10) {
                    OperationalDetailRow(title: "Profile", value: detail.title)
                    OperationalDetailRow(title: "Stage", value: workflowStageTitle(workflow.effectiveWorkflowStage))
                    OperationalDetailRow(title: "Status", value: detail.status)
                }
            }

            workflowSection("Printer and Paper") {
                VStack(alignment: .leading, spacing: 10) {
                    OperationalDetailRow(title: "Printer", value: printerName)
                    OperationalDetailRow(title: "Paper", value: paperName)
                    OperationalDetailRow(title: "Settings", value: currentSettingsSummary)
                }
            }

            workflowSection("Evidence") {
                VStack(alignment: .leading, spacing: 10) {
                    OperationalDetailRow(title: "Measurement", value: detail.measurement.measurementSourcePath?.nonEmpty ?? "Not measured yet")
                    OperationalDetailRow(title: "Artifacts", value: "\(detail.artifacts.count)")
                }
            }
        }
        .padding(16)
    }

    private var jobContextHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Job Ticket")
                .font(.headline)

            Text("Reference only. Use the main workspace for current-stage controls.")
                .font(AppTypography.trustSummarySupporting)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var printerName: String {
        workflow.workflowSelectedPrinter?.displayName.nonEmpty
            ?? detail.printer?.displayName.nonEmpty
            ?? detail.printerName.nonEmpty
            ?? "Not selected"
    }

    private var paperName: String {
        workflow.workflowSelectedPaper?.displayName.nonEmpty
            ?? detail.paper?.displayName.nonEmpty
            ?? detail.paperName.nonEmpty
            ?? "Not selected"
    }

    private var currentSettingsSummary: String {
        let mediaSetting = workflow.workflowMediaSetting.nonEmpty ?? detail.context.mediaSetting.nonEmpty
        let qualityMode = workflow.workflowQualityMode.nonEmpty ?? detail.context.qualityMode.nonEmpty
        let parts = [mediaSetting, qualityMode].compactMap { $0 }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " / ")
    }
}

struct NewProfileJobContextStrip: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Job Ticket")
                .font(.headline)

            Text(detail.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(printerName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(paperName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var printerName: String {
        workflow.workflowSelectedPrinter?.displayName.nonEmpty
            ?? detail.printer?.displayName.nonEmpty
            ?? detail.printerName.nonEmpty
            ?? "Not selected"
    }

    private var paperName: String {
        workflow.workflowSelectedPaper?.displayName.nonEmpty
            ?? detail.paper?.displayName.nonEmpty
            ?? detail.paperName.nonEmpty
            ?? "Not selected"
    }
}

struct NewProfileWorkflowWorkspaceView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let latestError = detail.latestError,
               detail.stage == .failed || detail.stage == .blocked {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Blocking command error")
                        .font(.headline)
                    Text(latestError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(18)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            switch workflow.effectiveWorkflowStage {
            case .context:
                NewProfileContextWorkspaceView(workflow: workflow, detail: detail, actions: actions)
            case .target:
                NewProfileTargetWorkspaceView(workflow: workflow, detail: detail, actions: actions)
            case .print:
                NewProfilePrintWorkspaceView(workflow: workflow, detail: detail, actions: actions)
            case .drying:
                NewProfileDryingWorkspaceView(workflow: workflow, detail: detail, actions: actions)
            case .measure:
                NewProfileMeasurementWorkspaceView(workflow: workflow, detail: detail, actions: actions)
            case .build, .review, .publish, .completed, .blocked, .failed:
                NewProfileReviewWorkspaceView(workflow: workflow, detail: detail, actions: actions)
            }
        }
    }
}

struct NewProfileContextWorkspaceView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            workflowSection("Profile Setup") {
                TextField("Profile name", text: $workflow.workflowProfileName)
                    .textFieldStyle(.roundedBorder)
                    .help("Name the profile so it is recognizable in Printer Profiles.")

                WorkflowColumns {
                    WorkflowContextSelectionCard(
                        title: "Printer",
                        primary: workflow.workflowSelectedPrinter?.displayName ?? "Choose Printer",
                        secondary: workflow.workflowSelectedPrinter.map(structuredPrinterIdentity)
                            ?? "Select the printer for this profile.",
                        chooseTitle: workflow.workflowSelectedPrinter == nil ? "Choose Printer" : "Change",
                        onChoose: {
                            workflow.presentWorkflowPrinterChooser()
                        },
                        createTitle: "New Printer",
                        onCreate: {
                            workflow.beginWorkflowPrinterCreation()
                        },
                        editTitle: workflow.workflowSelectedPrinter == nil ? nil : "Edit",
                        onEdit: {
                            workflow.presentWorkflowPrinterEditor()
                        }
                    )

                    WorkflowContextSelectionCard(
                        title: "Paper",
                        primary: workflow.workflowSelectedPaper?.displayName ?? "Choose Paper",
                        secondary: workflow.workflowSelectedPaper.map(structuredPaperIdentity)
                            ?? "Select the paper stock for this profile.",
                        chooseTitle: workflow.workflowSelectedPaper == nil ? "Choose Paper" : "Change",
                        onChoose: {
                            workflow.presentWorkflowPaperChooser()
                        },
                        createTitle: "New Paper",
                        onCreate: {
                            workflow.beginWorkflowPaperCreation()
                        },
                        editTitle: workflow.workflowSelectedPaper == nil ? nil : "Edit",
                        onEdit: {
                            workflow.presentWorkflowPaperEditor()
                        }
                    )
                }
            }

            workflowSection("Printer and paper settings") {
                if workflow.workflowSelectedPrinterID == nil || workflow.workflowSelectedPaperID == nil {
                    Text("Select a printer and paper before choosing saved print-path settings.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        if !workflow.workflowAvailablePrinterPaperPresets.isEmpty || workflow.workflowHasLegacyContextWithoutPreset {
                            Menu {
                                if workflow.workflowHasLegacyContextWithoutPreset {
                                    Button("Keep current job settings") {
                                        workflow.selectWorkflowPrinterPaperPreset(nil)
                                    }
                                }

                                ForEach(workflow.workflowAvailablePrinterPaperPresets, id: \.id) { preset in
                                    Button(preset.displayName) {
                                        workflow.selectWorkflowPrinterPaperPreset(preset.id)
                                    }
                                }
                            } label: {
                                Label(savedSettingsTitle, systemImage: "list.bullet")
                            }
                        }

                        Button(
                            workflow.workflowHasLegacyContextWithoutPreset
                                ? "Save As New Settings"
                                : "New Settings"
                        ) {
                            workflow.beginWorkflowPresetCreation()
                        }

                        if workflow.workflowSelectedPrinterPaperPreset != nil {
                            Button("Edit Settings") {
                                workflow.presentWorkflowPresetEditor()
                            }
                        }
                    }

                    if let preset = workflow.workflowSelectedPrinterPaperPreset {
                        WorkflowSummaryCard(title: preset.displayName) {
                            if !preset.printPath.isEmpty {
                                detailLine(title: "Print path", value: preset.printPath)
                            }
                            detailLine(title: "Media / quality", value: "\(preset.mediaSetting) / \(preset.qualityMode)")
                            detailLine(title: "Channels", value: currentWorkflowChannelSummary(workflow: workflow, detail: detail))
                            if let limits = presetLimitsSummary(preset) {
                                detailLine(title: "Limits", value: limits)
                            }
                            if !preset.notes.isEmpty {
                                detailLine(title: "Notes", value: preset.notes)
                            }
                        }
                    } else if workflow.workflowHasLegacyContextWithoutPreset {
                        WorkflowSummaryCard(title: "Current job settings") {
                            if !workflow.workflowPrintPath.isEmpty {
                                detailLine(title: "Print path", value: workflow.workflowPrintPath)
                            }
                            detailLine(title: "Media / quality", value: "\(workflow.workflowMediaSetting) / \(workflow.workflowQualityMode)")
                            detailLine(title: "Channels", value: currentWorkflowChannelSummary(workflow: workflow, detail: detail))
                            Text("Create Printer and Paper Settings to keep using structured command defaults for this print path.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if workflow.workflowAvailablePrinterPaperPresets.isEmpty {
                        Text("No saved printer and paper settings match this printer and paper yet.")
                            .font(AppTypography.trustSummarySupporting)
                            .foregroundStyle(.secondary)
                    }

                    if workflow.showsWorkflowStandalonePrintPathEditor {
                        WorkflowColumns {
                            TextField("Print path", text: $workflow.workflowPrintPath)
                                .textFieldStyle(.roundedBorder)

                            Picker("Media setting", selection: $workflow.workflowMediaSetting) {
                                Text("Select Media Setting").tag("")
                                ForEach(workflow.workflowAvailableMediaSettings, id: \.self) { mediaSetting in
                                    Text(mediaSetting).tag(mediaSetting)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        WorkflowColumns {
                            Picker("Quality mode", selection: $workflow.workflowQualityMode) {
                                Text("Select Quality Mode").tag("")
                                ForEach(workflow.workflowAvailableQualityModes, id: \.self) { qualityMode in
                                    Text(qualityMode).tag(qualityMode)
                                }
                            }
                            .pickerStyle(.menu)

                            TextField("Optional print-path notes", text: $workflow.workflowPrintPathNotes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2 ... 4)
                        }
                    } else {
                        TextField("Optional print-path notes", text: $workflow.workflowPrintPathNotes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2 ... 4)
                    }
                }
            }

            workflowSection("Measurement Setup") {
                WorkflowColumns {
                    Picker("Measurement Mode", selection: $workflow.workflowMeasurementMode) {
                        ForEach(measurementModes, id: \.self) { mode in
                            Text(workflowMeasurementModeLabel(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Strip mode is faster. Patch mode is slower but more robust on difficult media.")

                    TextField("Observer", text: $workflow.workflowMeasurementObserver)
                        .textFieldStyle(.roundedBorder)

                    TextField("Illuminant", text: $workflow.workflowMeasurementIlluminant)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Measurement notes", text: $workflow.workflowMeasurementNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 5)

                InlineGuidance(
                    title: "Measurement quality matters",
                    message: "Switch modes when strip reading is unreliable instead of forcing bad data through."
                )
            }
        }
    }

    private var savedSettingsTitle: String {
        if let preset = workflow.workflowSelectedPrinterPaperPreset {
            return preset.displayName
        }

        if workflow.workflowHasLegacyContextWithoutPreset {
            return "Current job settings"
        }

        return "Select Saved Settings"
    }
}

struct NewProfileTargetWorkspaceView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        workflowSection("Target Planning") {
            WorkflowColumns {
                TextField("Patch Count", text: $workflow.workflowPatchCount)
                    .textFieldStyle(.roundedBorder)
                    .help("Default patch count balances paper use, measurement time, and profile quality.")

                Toggle("Improve Neutrals", isOn: $workflow.workflowImproveNeutrals)
                    .help("Adds extra attention to grays and near-grays.")
            }

            InlineGuidance(
                title: "Patch count",
                message: "The default is usually the best balance of effort and accuracy. More patches do not compensate for the wrong media setting or weak measurements."
            )

            InlineGuidance(
                title: "Improve Neutrals",
                message: "Use this when smooth gray balance matters. It adds attention to grays and near-grays; it is not a general quality boost."
            )

            Toggle("Use Existing Profile to Help Target Planning", isOn: $workflow.workflowUsePlanningProfile)
                .help("Use only when the older profile is trustworthy enough to guide target placement.")

            if workflow.workflowUsePlanningProfile {
                Picker(
                    "Planning profile",
                    selection: Binding(
                        get: { workflow.workflowPlanningProfileID ?? "" },
                        set: { workflow.workflowPlanningProfileID = $0.isEmpty ? nil : $0 }
                    )
                ) {
                    Text("Select Profile").tag("")
                    ForEach(workflow.printerProfiles, id: \.id) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
            }

            InlineGuidance(
                title: "Planning profile",
                message: "Use a planning profile only when the older profile was trustworthy. It helps target placement; it does not repair a bad print path."
            )

            HStack(spacing: 10) {
                Text("Secondary")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button("Save Target Settings", action: actions.saveTargetSettings)
            }
        }
    }
}

struct NewProfilePrintWorkspaceView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            workflowSection("Print Target") {
                WorkflowColumns {
                    Toggle("Print Without Color Management", isOn: $workflow.workflowPrintWithoutColorManagement)
                        .help("Profiling targets must print without color management.")

                    TextField("Drying Time", text: $workflow.workflowDryingTimeMinutes)
                        .textFieldStyle(.roundedBorder)
                        .help("Wait time before measurement; unstable prints can create misleading measurements.")
                }

                InlineGuidance(
                    title: "Unmanaged target printing",
                    message: "Profiling targets must print unmanaged. If the app or driver changes the target colors, the profile will be built from the wrong data."
                )

                InlineGuidance(
                    title: "Drying time",
                    message: "Fine-art and high-ink papers often need more time to stabilize. Measuring too soon can bake temporary color into the profile."
                )

                HStack(spacing: 10) {
                    Text("Secondary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button("Save Print Settings", action: actions.savePrintSettings)
                }
            }

            workflowSection("Generated target artifacts") {
                workflowArtifactsList(workflow: workflow, artifacts: detail.artifacts.filter { $0.stage == .target || $0.stage == .print })
            }
        }
    }
}

struct NewProfileDryingWorkspaceView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        workflowSection("Drying") {
            WorkflowColumns {
                OperationalDetailRow(title: "Drying Time", value: "\(detail.printSettings.dryingTimeMinutes) minutes")
                OperationalDetailRow(title: "Printed at", value: detail.printSettings.printedAt ?? "Waiting")
            }

            WorkflowColumns {
                OperationalDetailRow(title: "Ready at", value: detail.printSettings.dryingReadyAt ?? "Waiting")
                OperationalDetailRow(title: "Countdown", value: dryingCountdown(detail))
            }
        }
    }
}

struct NewProfileMeasurementWorkspaceView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            workflowSection("Measure Target") {
                WorkflowColumns {
                    Picker("Measurement Mode", selection: $workflow.workflowMeasurementMode) {
                        ForEach(measurementModes, id: \.self) { mode in
                            Text(workflowMeasurementModeLabel(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Choose how the target will be measured.")

                    if workflow.workflowMeasurementMode == .scanFile {
                        HStack(spacing: 10) {
                            TextField("Scan file", text: $workflow.workflowScanFilePath)
                                .textFieldStyle(.roundedBorder)

                            Button("Choose File") {
                                if let file = PathSelection.chooseFile(
                                    initialPath: workflow.workflowScanFilePath,
                                    allowedExtensions: ["tif", "tiff"]
                                ) {
                                    workflow.workflowScanFilePath = file
                                }
                            }
                        }
                    }
                }

                InlineGuidance(
                    title: "Measurement mode",
                    message: "Use strip mode when reads are reliable. Switch to patch mode or scan-file measurement when strip detection creates bad data."
                )

                if workflow.workflowMeasurementMode == .scanFile && (workflow.effectiveScanFilePath?.isEmpty ?? true) {
                    InlineGuidance(
                        title: "Scan file required",
                        message: "Choose the scanned chart file before running measurement from a file."
                    )
                }

                OperationalDetailRow(
                    title: "Measurement source",
                    value: detail.measurement.measurementSourcePath ?? "Not measured yet"
                )

                if detail.measurement.hasMeasurementCheckpoint {
                    Text("Resume Measurement is available.")
                        .font(AppTypography.trustSummarySupporting)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Text("Secondary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button("Update Measurement Setup", action: actions.saveContext)
                }
            }

            workflowSection("Measurement artifacts") {
                workflowArtifactsList(workflow: workflow, artifacts: detail.artifacts.filter { $0.stage == .measure })
            }
        }
    }
}

struct NewProfileReviewWorkspaceView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if detail.stage == .build || workflow.effectiveWorkflowStage == .build {
                workflowSection("Build") {
                    OperationalDetailRow(
                        title: "Measurement source",
                        value: detail.measurement.measurementSourcePath ?? "Not available"
                    )

                    if detail.measurement.measurementSourcePath == nil {
                        InlineGuidance(
                            title: "Measurement required",
                            message: "Measure the target before building the profile."
                        )
                    }
                }
            }

            workflowSection("Review") {
                if let review = detail.review {
                    WorkflowColumns {
                        OperationalDetailRow(title: "Result", value: review.result)
                        OperationalDetailRow(title: "Verified against file", value: review.verifiedAgainstFile)
                    }

                    WorkflowColumns {
                        OperationalDetailRow(title: "Print settings", value: review.printSettings)
                        OperationalDetailRow(
                            title: "Last verification date",
                            value: review.lastVerificationDate ?? "Not yet published"
                        )
                    }

                    if let average = review.averageDe00 {
                        detailLine(title: "Average dE00", value: String(format: "%.2f", average))
                    }

                    if let maximum = review.maximumDe00 {
                        detailLine(title: "Maximum dE00", value: String(format: "%.2f", maximum))
                    }

                    if !review.notes.isEmpty {
                        detailLine(title: "Notes", value: review.notes)
                    }
                } else {
                    Text("Build the profile to populate the first review summary.")
                        .foregroundStyle(.secondary)
                }
            }

            workflowSection("Profile artifacts") {
                OperationalDetailRow(
                    title: "Measurement source",
                    value: detail.measurement.measurementSourcePath ?? "Not available"
                )

                if let publishedProfileId = detail.publishedProfileId {
                    OperationalDetailRow(title: "Published profile", value: publishedProfileId)
                }

                workflowArtifactsList(workflow: workflow, artifacts: detail.artifacts)

                if detail.publishedProfileId != nil {
                    Button("Open in Printer Profiles", action: actions.openPublishedProfileLibrary)
                }
            }
        }
    }
}

struct WorkflowPrinterChooserSheet: View {
    @ObservedObject var workflow: NewProfileWorkflowModel

    var body: some View {
        WorkflowCatalogChooserSheet(
            title: "Choose Printer",
            emptyMessage: "No printers exist yet. Create one to keep the workflow moving.",
            isEmpty: workflow.printers.isEmpty,
            onCreate: {
                workflow.beginWorkflowPrinterCreation()
            },
            onCancel: {
                workflow.dismissWorkflowContextSheet()
            }
        ) {
            ForEach(Array(workflow.printers), id: \.id) { printer in
                Button {
                    workflow.selectWorkflowPrinter(printer.id)
                } label: {
                    WorkflowCatalogChoiceRow(
                        title: printer.displayName,
                        subtitle: structuredPrinterIdentity(printer),
                        isSelected: workflow.workflowSelectedPrinterID == printer.id
                    )
                }
                .buttonStyle(SurfaceRowButtonStyle(isSelected: workflow.workflowSelectedPrinterID == printer.id))
            }
        }
    }
}

struct WorkflowPaperChooserSheet: View {
    @ObservedObject var workflow: NewProfileWorkflowModel

    var body: some View {
        WorkflowCatalogChooserSheet(
            title: "Choose Paper",
            emptyMessage: "No papers exist yet. Create one to keep the workflow moving.",
            isEmpty: workflow.papers.isEmpty,
            onCreate: {
                workflow.beginWorkflowPaperCreation()
            },
            onCancel: {
                workflow.dismissWorkflowContextSheet()
            }
        ) {
            ForEach(Array(workflow.papers), id: \.id) { paper in
                Button {
                    workflow.selectWorkflowPaper(paper.id)
                } label: {
                    WorkflowCatalogChoiceRow(
                        title: paper.displayName,
                        subtitle: structuredPaperIdentity(paper),
                        isSelected: workflow.workflowSelectedPaperID == paper.id
                    )
                }
                .buttonStyle(SurfaceRowButtonStyle(isSelected: workflow.workflowSelectedPaperID == paper.id))
            }
        }
    }
}

private struct WorkflowCatalogChoiceRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct WorkflowCatalogChooserSheet<Content: View>: View {
    let title: String
    let emptyMessage: String
    let isEmpty: Bool
    let onCreate: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text("Choose an existing item or create a new one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()

            Group {
                if isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(24)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            content()
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button("New", action: onCreate)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.regularMaterial)
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct WorkflowContextSelectionCard: View {
    let title: String
    let primary: String
    let secondary: String
    let chooseTitle: String
    let onChoose: () -> Void
    let createTitle: String
    let onCreate: () -> Void
    let editTitle: String?
    let onEdit: () -> Void

    var body: some View {
        WorkflowSummaryCard(title: title) {
            Text(primary)
                .font(.headline)
            Text(secondary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(chooseTitle, action: onChoose)
                Button(createTitle, action: onCreate)

                if let editTitle {
                    Button(editTitle, action: onEdit)
                }
            }
        }
    }
}

private struct WorkflowSummaryCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct InlineGuidance: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WorkflowColumns<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            content()
        }
    }
}

@MainActor
func workflowSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        Text(title)
            .font(.title3.weight(.semibold))
        content()
    }
    .padding(18)
    .background(workflowSectionBackground)
}

@MainActor
func workflowArtifactsList(workflow: NewProfileWorkflowModel, artifacts: [JobArtifactRecord]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        if artifacts.isEmpty {
            Text("No artifacts yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(artifacts, id: \.id) { artifact in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artifact.label)
                            .font(.headline)
                        Text(workflowArtifactSummary(artifact))
                            .font(AppTypography.trustSummarySupporting)
                            .foregroundStyle(.secondary)
                        if let path = artifact.path {
                            Text(path)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    Spacer()

                    if let path = artifact.path {
                        Button("Reveal") {
                            workflow.revealPathInFinder(path)
                        }
                        .buttonStyle(FooterLinkButtonStyle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private var workflowSectionBackground: some ShapeStyle {
    Color.secondary.opacity(0.08)
}

func workflowStageTitle(_ stage: WorkflowStage) -> String {
    workflowStageDisplayTitle(stage)
}

func workflowMeasurementModeLabel(_ mode: MeasurementMode) -> String {
    switch mode {
    case .strip:
        "Strip"
    case .patch:
        "Patch"
    case .scanFile:
        "Scan File"
    }
}

func workflowArtifactSummary(_ artifact: JobArtifactRecord) -> String {
    "\(workflowArtifactKindLabel(artifact.kind)) • \(workflowStageTitle(artifact.stage)) • \(artifact.status)"
}

func workflowArtifactKindLabel(_ kind: ArtifactKind) -> String {
    switch kind {
    case .ti1:
        "TI1"
    case .ti2:
        "TI2"
    case .printableChart:
        "Printable chart"
    case .chartTemplate:
        "Chart template"
    case .measurement:
        "Measurement"
    case .iccProfile:
        "ICC profile"
    case .verification:
        "Verification"
    case .diagnostic:
        "Diagnostic"
    case .working:
        "Working"
    }
}

func stageSummaryColor(_ state: WorkflowStageState) -> Color {
    switch state {
    case .completed:
        .green
    case .current:
        .accentColor
    case .upcoming:
        .secondary
    case .blocked:
        .red
    }
}

func stageSummarySubtitle(_ state: WorkflowStageState) -> String {
    switch state {
    case .completed:
        "Completed"
    case .current:
        "Current"
    case .upcoming:
        "Upcoming"
    case .blocked:
        "Blocked"
    }
}

func dryingCountdown(_ detail: NewProfileJobDetail) -> String {
    guard
        let readyAtString = detail.printSettings.dryingReadyAt,
        let readyAt = ISO8601DateFormatter().date(from: readyAtString)
    else {
        return "Waiting for Drying Time"
    }

    let remaining = Int(readyAt.timeIntervalSinceNow)
    if remaining <= 0 {
        return "Ready to Measure"
    }

    let minutes = remaining / 60
    let seconds = remaining % 60
    return String(format: "%02d:%02d remaining", minutes, seconds)
}

@MainActor
func currentWorkflowChannelSummary(workflow: NewProfileWorkflowModel, detail: NewProfileJobDetail) -> String {
    if let printer = workflow.workflowSelectedPrinter {
        return channelSetupSummary(printer.colorantFamily, printer.channelCount, printer.channelLabels)
    }

    return channelSetupSummary(
        detail.context.colorantFamily,
        detail.context.channelCount,
        detail.context.channelLabels
    )
}

private extension String {
    var nonEmpty: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }
}
