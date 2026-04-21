import SwiftUI

private let measurementModes: [MeasurementMode] = [.strip, .patch, .scanFile]

struct NewProfileWorkflowHeaderView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New Profile")
                    .font(.largeTitle.weight(.semibold))

                Text(detail.nextAction)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    StatusBadgeView(title: workflowStageTitle(workflow.effectiveWorkflowStage), tone: stageTone(for: detail))

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
                Button(workflow.workflowPrimaryActionTitle, action: actions.performPrimaryAction)
                    .disabled(!workflow.canRunWorkflowPrimaryAction)

                if let deletionTitle = workflow.currentWorkflowDeletionActionTitle {
                    Button(deletionTitle, role: .destructive, action: actions.requestWorkflowDeletion)
                }

                Button("Open Output Folder") {
                    workflow.revealPathInFinder(detail.workspacePath)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Open CLI Transcript") {
                    actions.openCliTranscript(detail.id)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(workflowSectionBackground)
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

struct NewProfileWorkflowTimelineView: View {
    let detail: NewProfileJobDetail

    var body: some View {
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
        .background(workflowSectionBackground)
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
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
            workflowSection("Context") {
                TextField("Profile name", text: $workflow.workflowProfileName)
                    .textFieldStyle(.roundedBorder)

                Picker(
                    "Printer",
                    selection: Binding(
                        get: { workflow.workflowSelectedPrinterID ?? "" },
                        set: { workflow.selectWorkflowPrinter($0.isEmpty ? nil : $0) }
                    )
                ) {
                    Text("Select Printer").tag("")
                    ForEach(workflow.printers, id: \.id) { printer in
                        Text(printer.displayName).tag(printer.id)
                    }
                }

                HStack(spacing: 10) {
                    Button("New Printer") {
                        workflow.beginWorkflowPrinterCreation()
                    }

                    if let selectedPrinter = workflow.workflowSelectedPrinter {
                        Text(selectedPrinter.displayName)
                            .font(AppTypography.trustSummarySupporting)
                            .foregroundStyle(.secondary)
                    }
                }

                if workflow.showWorkflowPrinterForm {
                    PrinterEditorForm(
                        title: workflow.workflowPrinterDraft.title,
                        draft: $workflow.workflowPrinterDraft,
                        saveTitle: "Create Printer",
                        secondaryTitle: "Cancel",
                        isSaveDisabled: !workflow.isWorkflowPrinterDraftValid,
                        onSave: actions.createWorkflowPrinter,
                        onSecondary: {
                            workflow.cancelWorkflowPrinterCreation()
                        }
                    )
                }

                Divider()

                Picker(
                    "Paper",
                    selection: Binding(
                        get: { workflow.workflowSelectedPaperID ?? "" },
                        set: { workflow.selectWorkflowPaper($0.isEmpty ? nil : $0) }
                    )
                ) {
                    Text("Select Paper").tag("")
                    ForEach(workflow.papers, id: \.id) { paper in
                        Text(paper.displayName).tag(paper.id)
                    }
                }

                HStack(spacing: 10) {
                    Button("New Paper") {
                        workflow.beginWorkflowPaperCreation()
                    }

                    if let selectedPaper = workflow.workflowSelectedPaper {
                        Text(selectedPaper.displayName)
                            .font(AppTypography.trustSummarySupporting)
                            .foregroundStyle(.secondary)
                    }
                }

                if workflow.showWorkflowPaperForm {
                    PaperEditorForm(
                        title: workflow.workflowPaperDraft.title,
                        draft: $workflow.workflowPaperDraft,
                        saveTitle: "Create Paper",
                        secondaryTitle: "Cancel",
                        isSaveDisabled: !workflow.isWorkflowPaperDraftValid,
                        onSave: actions.createWorkflowPaper,
                        onSecondary: {
                            workflow.cancelWorkflowPaperCreation()
                        }
                    )
                }
            }

            workflowSection("Printer and paper settings") {
                if workflow.workflowSelectedPrinterID == nil || workflow.workflowSelectedPaperID == nil {
                    Text("Select a printer and paper before choosing saved print-path settings.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "Saved settings",
                        selection: Binding(
                            get: { workflow.workflowSelectedPrinterPaperPresetID ?? "" },
                            set: { workflow.selectWorkflowPrinterPaperPreset($0.isEmpty ? nil : $0) }
                        )
                    ) {
                        Text(workflow.workflowHasLegacyContextWithoutPreset ? "Keep Legacy Job Settings" : "Select Saved Settings").tag("")
                        ForEach(workflow.workflowAvailablePrinterPaperPresets, id: \.id) { preset in
                            Text(preset.displayName).tag(preset.id)
                        }
                    }

                    HStack(spacing: 10) {
                        Button(workflow.workflowHasLegacyContextWithoutPreset ? "Save Legacy Settings as Preset" : "New Printer and Paper Settings") {
                            workflow.beginWorkflowPresetCreation()
                        }
                        .disabled(workflow.workflowSelectedPrinterID == nil || workflow.workflowSelectedPaperID == nil)

                        if let preset = workflow.workflowSelectedPrinterPaperPreset {
                            Text(preset.displayName)
                                .font(AppTypography.trustSummarySupporting)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let preset = workflow.workflowSelectedPrinterPaperPreset {
                        VStack(alignment: .leading, spacing: 8) {
                            if !preset.printPath.isEmpty {
                                Text(preset.printPath)
                                    .font(.subheadline)
                            }
                            Text("\(preset.mediaSetting) / \(preset.qualityMode)")
                                .font(.subheadline)
                            Text(currentWorkflowChannelSummary(workflow: workflow, detail: detail))
                                .font(AppTypography.trustSummarySupporting)
                                .foregroundStyle(.secondary)
                            if let limits = presetLimitsSummary(preset) {
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
                    } else if workflow.workflowHasLegacyContextWithoutPreset {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("This job still uses legacy saved values.")
                                .font(.headline)
                            if !workflow.workflowPrintPath.isEmpty {
                                Text(workflow.workflowPrintPath)
                                    .font(.subheadline)
                            }
                            Text("\(workflow.workflowMediaSetting) / \(workflow.workflowQualityMode)")
                                .font(.subheadline)
                            Text(currentWorkflowChannelSummary(workflow: workflow, detail: detail))
                                .font(AppTypography.trustSummarySupporting)
                                .foregroundStyle(.secondary)
                            Text("Create Printer and Paper Settings to keep using structured command defaults for this print path.")
                                .font(AppTypography.trustSummarySupporting)
                                .foregroundStyle(.secondary)
                        }
                    } else if workflow.workflowAvailablePrinterPaperPresets.isEmpty {
                        Text("No saved printer and paper settings match this printer and paper yet.")
                            .font(AppTypography.trustSummarySupporting)
                            .foregroundStyle(.secondary)
                    }

                    if workflow.showWorkflowPresetForm {
                        PrinterPaperPresetEditorForm(
                            title: workflow.workflowPresetDraft.title,
                            draft: $workflow.workflowPresetDraft,
                            printers: workflow.printers,
                            papers: workflow.papers,
                            lockPrinterAndPaperSelection: true,
                            saveTitle: "Save Settings",
                            secondaryTitle: "Cancel",
                            isSaveDisabled: !workflow.isWorkflowPresetDraftValid,
                            onSave: actions.createWorkflowPreset,
                            onSecondary: {
                                workflow.cancelWorkflowPresetCreation()
                            }
                        )
                    }
                }

                if workflow.showsWorkflowStandalonePrintPathEditor {
                    TextField("Print path", text: $workflow.workflowPrintPath)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Optional print-path notes", text: $workflow.workflowPrintPathNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 5)
            }

            workflowSection("Measurement assumptions") {
                Picker("Measurement Mode", selection: $workflow.workflowMeasurementMode) {
                    ForEach(measurementModes, id: \.self) { mode in
                        Text(workflowMeasurementModeLabel(mode)).tag(mode)
                    }
                }

                HStack(spacing: 12) {
                    TextField("Observer", text: $workflow.workflowMeasurementObserver)
                        .textFieldStyle(.roundedBorder)
                    TextField("Illuminant", text: $workflow.workflowMeasurementIlluminant)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Measurement assumptions", text: $workflow.workflowMeasurementNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 5)

                Button("Save Context", action: actions.saveContext)
                    .disabled(!workflow.canSaveWorkflowContext)
            }
        }
    }
}

struct NewProfileTargetWorkspaceView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        workflowSection("Target") {
            TextField("Patch Count", text: $workflow.workflowPatchCount)
                .textFieldStyle(.roundedBorder)

            Toggle("Improve Neutrals", isOn: $workflow.workflowImproveNeutrals)
            Toggle("Use Existing Profile to Help Target Planning", isOn: $workflow.workflowUsePlanningProfile)

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
            }

            HStack(spacing: 10) {
                Button("Save Target Settings", action: actions.saveTargetSettings)

                Button("Generate Target", action: actions.generateTarget)
                    .disabled(detail.isCommandRunning)
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
            workflowSection("Print") {
                Toggle("Print Without Color Management", isOn: $workflow.workflowPrintWithoutColorManagement)

                TextField("Drying Time", text: $workflow.workflowDryingTimeMinutes)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Save Print Settings", action: actions.savePrintSettings)

                    Button("Mark Chart as Printed", action: actions.markChartPrinted)
                        .disabled(detail.isCommandRunning)
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
            OperationalDetailRow(title: "Drying Time", value: "\(detail.printSettings.dryingTimeMinutes) minutes")
            OperationalDetailRow(title: "Printed at", value: detail.printSettings.printedAt ?? "Waiting")
            OperationalDetailRow(title: "Ready at", value: detail.printSettings.dryingReadyAt ?? "Waiting")
            OperationalDetailRow(title: "Countdown", value: dryingCountdown(detail))

            Button("Mark Ready to Measure", action: actions.markReadyToMeasure)
                .disabled(detail.isCommandRunning)
        }
    }
}

struct NewProfileMeasurementWorkspaceView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail
    let actions: NewProfileWorkflowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            workflowSection("Measure") {
                Picker("Measurement Mode", selection: $workflow.workflowMeasurementMode) {
                    ForEach(measurementModes, id: \.self) { mode in
                        Text(workflowMeasurementModeLabel(mode)).tag(mode)
                    }
                }

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
                    Button("Save Context", action: actions.saveContext)

                    Button(detail.measurement.hasMeasurementCheckpoint ? "Resume Measurement" : "Measure", action: actions.startMeasurement)
                        .disabled(detail.isCommandRunning || !workflow.canRunWorkflowPrimaryAction)
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

                    Button("Build Profile", action: actions.buildProfile)
                        .disabled(detail.isCommandRunning || detail.measurement.measurementSourcePath == nil)
                }
            }

            workflowSection("Review") {
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

            workflowSection("Profile artifacts") {
                OperationalDetailRow(
                    title: "Measurement source",
                    value: detail.measurement.measurementSourcePath ?? "Not available"
                )

                if let publishedProfileId = detail.publishedProfileId {
                    OperationalDetailRow(title: "Published profile", value: publishedProfileId)
                }

                workflowArtifactsList(workflow: workflow, artifacts: detail.artifacts)

                HStack(spacing: 10) {
                    Button("Publish", action: actions.publishProfile)
                        .disabled(detail.review == nil || detail.isCommandRunning || detail.publishedProfileId != nil)

                    if detail.publishedProfileId != nil {
                        Button("Open in Printer Profiles", action: actions.openPublishedProfileLibrary)
                    }
                }
            }
        }
    }
}

struct NewProfileWorkflowInspectorView: View {
    @ObservedObject var workflow: NewProfileWorkflowModel
    let detail: NewProfileJobDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            workflowInspectorSection(title: "Recommended", body: detail.nextAction)
            workflowInspectorSection(title: "Advanced", body: advancedInspectorCopy)

            VStack(alignment: .leading, spacing: 10) {
                Text("Technical")
                    .font(.headline)

                OperationalDetailRow(title: "Stage", value: workflowStageTitle(detail.stage))
                OperationalDetailRow(title: "Workspace", value: detail.workspacePath)
                OperationalDetailRow(title: "Measurement Mode", value: workflowMeasurementModeLabel(workflow.workflowMeasurementMode))
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
        .background(workflowSectionBackground)
    }

    private var advancedInspectorCopy: String {
        switch workflow.effectiveWorkflowStage {
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
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

@MainActor
func workflowInspectorSection(title: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.headline)
        Text(body)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

private var workflowSectionBackground: some ShapeStyle {
    Color.secondary.opacity(0.08)
}

func workflowStageTitle(_ stage: WorkflowStage) -> String {
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
