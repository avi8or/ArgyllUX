import SwiftUI

struct NewProfileWorkflowView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppModel

    private let measurementModes: [MeasurementMode] = [.strip, .patch, .scanFile]

    var body: some View {
        Group {
            if let detail = model.activeNewProfileDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(detail)

                        HStack(alignment: .top, spacing: 18) {
                            timeline(detail)
                                .frame(width: 220)

                            workspace(detail)
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            inspector(detail)
                                .frame(width: 280)
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ProgressView("Opening New Profile")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func header(_ detail: NewProfileJobDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New Profile")
                    .font(.largeTitle.weight(.semibold))

                Text(detail.nextAction)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    stageBadge(title: stageTitle(model.effectiveWorkflowStage), tone: stageTone(for: detail))

                    Text(detail.status)
                        .font(AppTypography.shellUtility)
                        .foregroundStyle(.secondary)

                    if detail.isCommandRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(detail.title)
                    .font(.headline)

                Text("Job ID: \(detail.id)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button(model.workflowPrimaryActionTitle) {
                    Task { await model.performWorkflowPrimaryAction() }
                }
                .disabled(!model.canRunWorkflowPrimaryAction)

                if model.canDeleteCurrentWorkflow {
                    Button(ActiveWorkCopy.deleteActionTitle, role: .destructive) {
                        model.requestCurrentWorkflowDeletion()
                    }
                }

                Button("Open Output Folder") {
                    model.revealPathInFinder(detail.workspacePath)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Open CLI Transcript") {
                    openWindow(id: CliTranscriptWindowView.windowID)
                    Task { await model.openCliTranscript(jobId: detail.id) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func timeline(_ detail: NewProfileJobDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Timeline")
                .font(.title3.weight(.semibold))

            ForEach(detail.stageTimeline, id: \.stage) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(stageSummaryColor(item.state))
                        .frame(width: 10, height: 10)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        Text(stageSummarySubtitle(item.state))
                            .font(AppTypography.trustSummarySupporting)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    @ViewBuilder
    private func workspace(_ detail: NewProfileJobDetail) -> some View {
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
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            switch model.effectiveWorkflowStage {
            case .context:
                contextWorkspace(detail)
            case .target:
                targetWorkspace(detail)
            case .print:
                printWorkspace(detail)
            case .drying:
                dryingWorkspace(detail)
            case .measure:
                measurementWorkspace(detail)
            case .build, .review, .publish, .completed:
                reviewWorkspace(detail)
            case .blocked, .failed:
                reviewWorkspace(detail)
            }
        }
    }

    private func contextWorkspace(_ detail: NewProfileJobDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            workspaceSection("Context") {
                TextField("Profile name", text: $model.workflowProfileName)
                    .textFieldStyle(.roundedBorder)

                Picker(
                    "Printer",
                    selection: Binding(
                        get: { model.workflowSelectedPrinterID ?? "" },
                        set: { model.selectWorkflowPrinter($0.isEmpty ? nil : $0) }
                    )
                ) {
                    Text("Select Printer").tag("")
                    ForEach(model.printers, id: \.id) { printer in
                        Text(printer.displayName).tag(printer.id)
                    }
                }

                HStack(spacing: 10) {
                    Button("New Printer") {
                        model.beginWorkflowPrinterCreation()
                    }

                    if let selectedPrinter = model.workflowSelectedPrinter {
                        Text(selectedPrinter.displayName)
                            .font(AppTypography.trustSummarySupporting)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.showWorkflowPrinterForm {
                    PrinterEditorForm(
                        title: model.workflowPrinterDraft.title,
                        draft: $model.workflowPrinterDraft,
                        saveTitle: "Create Printer",
                        secondaryTitle: "Cancel",
                        isSaveDisabled: !model.isWorkflowPrinterDraftValid,
                        onSave: {
                            Task { await model.createWorkflowPrinter() }
                        },
                        onSecondary: {
                            model.cancelWorkflowPrinterCreation()
                        }
                    )
                }

                Divider()

                Picker(
                    "Paper",
                    selection: Binding(
                        get: { model.workflowSelectedPaperID ?? "" },
                        set: { model.selectWorkflowPaper($0.isEmpty ? nil : $0) }
                    )
                ) {
                    Text("Select Paper").tag("")
                    ForEach(model.papers, id: \.id) { paper in
                        Text(paper.displayName).tag(paper.id)
                    }
                }

                HStack(spacing: 10) {
                    Button("New Paper") {
                        model.beginWorkflowPaperCreation()
                    }

                    if let selectedPaper = model.workflowSelectedPaper {
                        Text(selectedPaper.displayName)
                            .font(AppTypography.trustSummarySupporting)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.showWorkflowPaperForm {
                    PaperEditorForm(
                        title: model.workflowPaperDraft.title,
                        draft: $model.workflowPaperDraft,
                        saveTitle: "Create Paper",
                        secondaryTitle: "Cancel",
                        isSaveDisabled: !model.isWorkflowPaperDraftValid,
                        onSave: {
                            Task { await model.createWorkflowPaper() }
                        },
                        onSecondary: {
                            model.cancelWorkflowPaperCreation()
                        }
                    )
                }
            }

            workspaceSection("Printer and paper settings") {
                if model.workflowSelectedPrinterID == nil || model.workflowSelectedPaperID == nil {
                    Text("Select a printer and paper before choosing saved print-path settings.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "Saved settings",
                        selection: Binding(
                            get: { model.workflowSelectedPrinterPaperPresetID ?? "" },
                            set: { model.selectWorkflowPrinterPaperPreset($0.isEmpty ? nil : $0) }
                        )
                    ) {
                        Text(model.workflowHasLegacyContextWithoutPreset ? "Keep Legacy Job Settings" : "Select Saved Settings").tag("")
                        ForEach(model.workflowAvailablePrinterPaperPresets, id: \.id) { preset in
                            Text(preset.displayName).tag(preset.id)
                        }
                    }

                    HStack(spacing: 10) {
                        Button(model.workflowHasLegacyContextWithoutPreset ? "Save Legacy Settings as Preset" : "New Printer and Paper Settings") {
                            model.beginWorkflowPresetCreation()
                        }
                        .disabled(model.workflowSelectedPrinterID == nil || model.workflowSelectedPaperID == nil)

                        if let preset = model.workflowSelectedPrinterPaperPreset {
                            Text(preset.displayName)
                                .font(AppTypography.trustSummarySupporting)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let preset = model.workflowSelectedPrinterPaperPreset {
                        VStack(alignment: .leading, spacing: 8) {
                            if !preset.printPath.isEmpty {
                                Text(preset.printPath)
                                    .font(.subheadline)
                            }
                            Text("\(preset.mediaSetting) / \(preset.qualityMode)")
                                .font(.subheadline)
                            Text(currentWorkflowChannelSummary(detail))
                                .font(AppTypography.trustSummarySupporting)
                                .foregroundStyle(.secondary)
                            if let limits = workflowPresetLimitsSummary(preset) {
                                Text(limits)
                                    .font(AppTypography.trustSummarySupporting)
                                    .foregroundStyle(.secondary)
                            }
                            if !preset.notes.isEmpty {
                                Text(preset.notes)
                                    .font(AppTypography.trustSummarySupporting)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if model.workflowHasLegacyContextWithoutPreset {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("This job still uses legacy saved values.")
                                .font(.headline)
                            if !model.workflowPrintPath.isEmpty {
                                Text(model.workflowPrintPath)
                                    .font(.subheadline)
                            }
                            Text("\(model.workflowMediaSetting) / \(model.workflowQualityMode)")
                                .font(.subheadline)
                            Text(currentWorkflowChannelSummary(detail))
                                .font(AppTypography.trustSummarySupporting)
                                .foregroundStyle(.secondary)
                            Text("Create Printer and Paper Settings to keep using structured command defaults for this print path.")
                                .font(AppTypography.trustSummarySupporting)
                                .foregroundStyle(.secondary)
                        }
                    } else if model.workflowAvailablePrinterPaperPresets.isEmpty {
                        Text("No saved printer and paper settings match this printer and paper yet.")
                            .font(AppTypography.trustSummarySupporting)
                            .foregroundStyle(.secondary)
                    }

                    if model.showWorkflowPresetForm {
                        PrinterPaperPresetEditorForm(
                            title: model.workflowPresetDraft.title,
                            draft: $model.workflowPresetDraft,
                            printers: model.printers,
                            papers: model.papers,
                            lockPrinterAndPaperSelection: true,
                            saveTitle: "Save Settings",
                            secondaryTitle: "Cancel",
                            isSaveDisabled: !model.isWorkflowPresetDraftValid,
                            onSave: {
                                Task { await model.createWorkflowPreset() }
                            },
                            onSecondary: {
                                model.cancelWorkflowPresetCreation()
                            }
                        )
                    }
                }

                if model.showsWorkflowStandalonePrintPathEditor {
                    TextField("Print path", text: $model.workflowPrintPath)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Optional print-path notes", text: $model.workflowPrintPathNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
            }

            workspaceSection("Measurement assumptions") {
                Picker("Measurement Mode", selection: $model.workflowMeasurementMode) {
                    ForEach(measurementModes, id: \.self) { mode in
                        Text(measurementModeLabel(mode)).tag(mode)
                    }
                }

                HStack(spacing: 12) {
                    TextField("Observer", text: $model.workflowMeasurementObserver)
                        .textFieldStyle(.roundedBorder)
                    TextField("Illuminant", text: $model.workflowMeasurementIlluminant)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Measurement assumptions", text: $model.workflowMeasurementNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)

                Button("Save Context") {
                    Task { await model.saveWorkflowContext() }
                }
                .disabled(!model.canSaveWorkflowContext)
            }
        }
    }

    private func targetWorkspace(_ detail: NewProfileJobDetail) -> some View {
        workspaceSection("Target") {
            TextField("Patch Count", text: $model.workflowPatchCount)
                .textFieldStyle(.roundedBorder)

            Toggle("Improve Neutrals", isOn: $model.workflowImproveNeutrals)
            Toggle("Use Existing Profile to Help Target Planning", isOn: $model.workflowUsePlanningProfile)

            if model.workflowUsePlanningProfile {
                Picker(
                    "Planning profile",
                    selection: Binding(
                        get: { model.workflowPlanningProfileID ?? "" },
                        set: { model.workflowPlanningProfileID = $0.isEmpty ? nil : $0 }
                    )
                ) {
                    Text("Select Profile").tag("")
                    ForEach(model.printerProfiles, id: \.id) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Save Target Settings") {
                    Task { await model.saveTargetSettings() }
                }

                Button("Generate Target") {
                    Task { await model.generateTarget() }
                }
                .disabled(detail.isCommandRunning)
            }
        }
    }

    private func printWorkspace(_ detail: NewProfileJobDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            workspaceSection("Print") {
                Toggle("Print Without Color Management", isOn: $model.workflowPrintWithoutColorManagement)

                TextField("Drying Time", text: $model.workflowDryingTimeMinutes)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Save Print Settings") {
                        Task { await model.savePrintSettings() }
                    }

                    Button("Mark Chart as Printed") {
                        Task { await model.markChartPrinted() }
                    }
                    .disabled(detail.isCommandRunning)
                }
            }

            workspaceSection("Generated target artifacts") {
                artifactsList(detail.artifacts.filter { $0.stage == .target || $0.stage == .print })
            }
        }
    }

    private func dryingWorkspace(_ detail: NewProfileJobDetail) -> some View {
        workspaceSection("Drying") {
            OperationalDetailRow(title: "Drying Time", value: "\(detail.printSettings.dryingTimeMinutes) minutes")
            OperationalDetailRow(title: "Printed at", value: detail.printSettings.printedAt ?? "Waiting")
            OperationalDetailRow(title: "Ready at", value: detail.printSettings.dryingReadyAt ?? "Waiting")
            OperationalDetailRow(title: "Countdown", value: dryingCountdown(detail))

            Button("Mark Ready to Measure") {
                Task { await model.markReadyToMeasure() }
            }
            .disabled(detail.isCommandRunning)
        }
    }

    private func measurementWorkspace(_ detail: NewProfileJobDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            workspaceSection("Measure") {
                Picker("Measurement Mode", selection: $model.workflowMeasurementMode) {
                    ForEach(measurementModes, id: \.self) { mode in
                        Text(measurementModeLabel(mode)).tag(mode)
                    }
                }

                if model.workflowMeasurementMode == .scanFile {
                    HStack(spacing: 10) {
                        TextField("Scan file", text: $model.workflowScanFilePath)
                            .textFieldStyle(.roundedBorder)

                        Button("Choose File") {
                            if let file = PathSelection.chooseFile(
                                initialPath: model.workflowScanFilePath,
                                allowedExtensions: ["tif", "tiff"]
                            ) {
                                model.workflowScanFilePath = file
                            }
                        }
                    }
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
                    Button("Save Context") {
                        Task { await model.saveWorkflowContext() }
                    }

                    Button(detail.measurement.hasMeasurementCheckpoint ? "Resume Measurement" : "Measure") {
                        Task { await model.startMeasurement() }
                    }
                    .disabled(detail.isCommandRunning || !model.canRunWorkflowPrimaryAction)
                }
            }

            workspaceSection("Measurement artifacts") {
                artifactsList(detail.artifacts.filter { $0.stage == .measure })
            }
        }
    }

    private func reviewWorkspace(_ detail: NewProfileJobDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if detail.stage == .build || model.effectiveWorkflowStage == .build {
                workspaceSection("Build") {
                    OperationalDetailRow(
                        title: "Measurement source",
                        value: detail.measurement.measurementSourcePath ?? "Not available"
                    )

                    Button("Build Profile") {
                        Task { await model.buildProfile() }
                    }
                    .disabled(detail.isCommandRunning || detail.measurement.measurementSourcePath == nil)
                }
            }

            workspaceSection("Review") {
                if let review = detail.review {
                    OperationalDetailRow(title: "Result", value: review.result)
                    OperationalDetailRow(title: "Verified against file", value: review.verifiedAgainstFile)
                    OperationalDetailRow(title: "Print settings", value: review.printSettings)
                    OperationalDetailRow(
                        title: "Last verification date",
                        value: review.lastVerificationDate ?? "Not yet published"
                    )

                    if let average = review.averageDe00 {
                        OperationalDetailRow(title: "Average dE00", value: String(format: "%.2f", average))
                    }

                    if let maximum = review.maximumDe00 {
                        OperationalDetailRow(title: "Maximum dE00", value: String(format: "%.2f", maximum))
                    }

                    if !review.notes.isEmpty {
                        OperationalDetailRow(title: "Notes", value: review.notes)
                    }
                } else {
                    Text("Build the profile to populate the first review summary.")
                        .foregroundStyle(.secondary)
                }
            }

            workspaceSection("Profile artifacts") {
                OperationalDetailRow(
                    title: "Measurement source",
                    value: detail.measurement.measurementSourcePath ?? "Not available"
                )

                if let publishedProfileId = detail.publishedProfileId {
                    OperationalDetailRow(title: "Published profile", value: publishedProfileId)
                }

                artifactsList(detail.artifacts)

                HStack(spacing: 10) {
                    Button("Publish") {
                        Task { await model.publishProfile() }
                    }
                    .disabled(detail.review == nil || detail.isCommandRunning || detail.publishedProfileId != nil)

                    if detail.publishedProfileId != nil {
                        Button("Open in Printer Profiles") {
                            model.openPublishedProfileLibrary()
                        }
                    }
                }
            }
        }
    }

    private func inspector(_ detail: NewProfileJobDetail) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            inspectorSection(title: "Recommended", body: detail.nextAction)

            inspectorSection(title: "Advanced", body: advancedInspectorCopy(detail))

            VStack(alignment: .leading, spacing: 10) {
                Text("Technical")
                    .font(.headline)

                OperationalDetailRow(title: "Stage", value: stageTitle(detail.stage))
                OperationalDetailRow(title: "Workspace", value: detail.workspacePath)
                OperationalDetailRow(title: "Toolchain", value: model.argyllStatusLabel)
                OperationalDetailRow(
                    title: "Measurement Mode",
                    value: measurementModeLabel(model.workflowMeasurementMode)
                )
                OperationalDetailRow(title: "Command state", value: detail.isCommandRunning ? "Running" : "Idle")

                if detail.measurement.hasMeasurementCheckpoint {
                    OperationalDetailRow(title: "Measurement checkpoint", value: "Available")
                }

                if let latestError = detail.latestError {
                    OperationalDetailRow(title: "Latest error", value: latestError)
                }
            }
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func artifactsList(_ artifacts: [JobArtifactRecord]) -> some View {
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
                            Text(artifactSummary(artifact))
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
                                model.revealPathInFinder(path)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func workspaceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .padding(18)
        .background(sectionBackground)
    }

    private func inspectorSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func stageBadge(title: String, tone: StatusBadgeView.Tone) -> some View {
        StatusBadgeView(title: title, tone: tone)
    }

    private var sectionBackground: some ShapeStyle {
        Color.secondary.opacity(0.08)
    }

    private func stageTitle(_ stage: WorkflowStage) -> String {
        switch stage {
        case .context:
            "Context"
        case .target:
            "Target"
        case .print:
            "Print"
        case .drying:
            "Drying"
        case .measure:
            "Measure"
        case .build:
            "Build"
        case .review:
            "Review"
        case .publish:
            "Publish"
        case .completed:
            "Completed"
        case .blocked:
            "Blocked"
        case .failed:
            "Failed"
        }
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

    private func stageSummaryColor(_ state: WorkflowStageState) -> Color {
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

    private func stageSummarySubtitle(_ state: WorkflowStageState) -> String {
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

    private func measurementModeLabel(_ mode: MeasurementMode) -> String {
        switch mode {
        case .strip:
            "Strip"
        case .patch:
            "Patch"
        case .scanFile:
            "Scan File"
        }
    }

    private func advancedInspectorCopy(_ detail: NewProfileJobDetail) -> String {
        switch model.effectiveWorkflowStage {
        case .context:
            return "Save the profile context before moving into target planning. Printer and paper settings stay attached to this job rather than becoming a separate workflow."
        case .target:
            return "Target planning persists in Rust, including Patch Count and whether an existing profile should help target planning."
        case .print:
            return "Print step keeps the unmanaged-printing requirement explicit and holds the generated target artifacts with the job."
        case .drying:
            return "Drying Time is durable. The countdown is shell-only, but the printed and ready timestamps live in the engine."
        case .measure:
            return detail.measurement.hasMeasurementCheckpoint
                ? "Measurement can resume because checkpoint artifacts were found in the job workspace."
                : "Argyll command output appears in the CLI Transcript window while commands run."
        case .build:
            return "Build runs colprof and profcheck in sequence, then stores the first result summary back onto the job."
        case .review, .publish:
            return "Review is intentionally explicit. Publishing creates the library record only after you inspect the result."
        case .completed:
            return "Completed jobs stay resumable through their linked printer profile, artifacts, and command transcript."
        case .blocked, .failed:
            return "A command failed on this job. Argyll command output appears in the CLI Transcript window."
        }
    }

    private func artifactSummary(_ artifact: JobArtifactRecord) -> String {
        "\(artifactKindLabel(artifact.kind)) • \(stageTitle(artifact.stage)) • \(artifact.status)"
    }

    private func artifactKindLabel(_ kind: ArtifactKind) -> String {
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

    private func dryingCountdown(_ detail: NewProfileJobDetail) -> String {
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

    private func currentWorkflowChannelSummary(_ detail: NewProfileJobDetail) -> String {
        if let printer = model.workflowSelectedPrinter {
            return channelSetupSummary(printer.colorantFamily, printer.channelCount, printer.channelLabels)
        }

        return channelSetupSummary(
            detail.context.colorantFamily,
            detail.context.channelCount,
            detail.context.channelLabels
        )
    }

    private func workflowPresetLimitsSummary(_ preset: PrinterPaperPresetRecord) -> String? {
        var parts: [String] = []
        if let totalInkLimitPercent = preset.totalInkLimitPercent {
            parts.append("TAC \(totalInkLimitPercent)%")
        }
        if let blackInkLimitPercent = preset.blackInkLimitPercent {
            parts.append("Black \(blackInkLimitPercent)%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
