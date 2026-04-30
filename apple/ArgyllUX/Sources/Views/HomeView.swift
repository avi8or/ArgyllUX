import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel

    private let taskColumns = [
        GridItem(.flexible(minimum: 180), spacing: 10),
        GridItem(.flexible(minimum: 180), spacing: 10),
    ]

    private var newProfileAction: LauncherAction? {
        model.availableLauncherActions.first { $0.kind == .newProfile }
    }

    private var troubleshootAction: LauncherAction? {
        model.availableLauncherActions.first { $0.kind == .route(.troubleshoot) }
    }

    private var supportingRouteActions: [LauncherAction] {
        model.availableLauncherActions.filter {
            switch $0.kind {
            case .route(.inspect), .route(.blackAndWhiteTuning):
                return true
            case .newProfile, .route, .planned:
                return false
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width < 980 {
                ScrollView {
                    compactDashboard
                        .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                desktopDashboard
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var desktopDashboard: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    primaryLauncherPanel
                    supportingWorkspacesPanel
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                activeWorkPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 18) {
                    profileHealthPanel
                    readinessPanel
                }
                .frame(width: 360, alignment: .topLeading)
            }
        }
    }

    private var compactDashboard: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            primaryLauncherPanel
            activeWorkPanel
            profileHealthPanel
            readinessPanel
            supportingWorkspacesPanel
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Home")
                .font(.largeTitle.weight(.semibold))
            Text("Start the right task, resume work that needs attention, and check whether recent profiles are trustworthy.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var primaryLauncherPanel: some View {
        dashboardPanel(
            title: "Start a Task",
            subtitle: "Begin with the profile you need to make or the print problem you need to understand."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let newProfileAction {
                    launcherButton(
                        action: newProfileAction,
                        symbolName: "plus.circle.fill",
                        tone: .ready
                    )
                }

                if let troubleshootAction {
                    launcherButton(
                        action: troubleshootAction,
                        symbolName: "stethoscope",
                        tone: .attention
                    )
                }
            }
        }
    }

    private var supportingWorkspacesPanel: some View {
        dashboardPanel(
            title: "Understand Existing Work",
            subtitle: "Use focused workspaces for analysis and monochrome checks without leaving the shell."
        ) {
            LazyVGrid(columns: taskColumns, alignment: .leading, spacing: 10) {
                ForEach(supportingRouteActions) { action in
                    launcherButton(
                        action: action,
                        symbolName: symbolName(for: action),
                        tone: .attention,
                        isCompact: true
                    )
                }
            }
        }
    }

    private var activeWorkPanel: some View {
        dashboardPanel(
            title: "Active Work",
            subtitle: "Resume jobs with a saved next step. The dock appears only when work is active or resumable."
        ) {
            if model.activeWorkItems.isEmpty {
                dashboardEmptyState("No active work. Start a New Profile when you are ready to print and measure a target.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.activeWorkItems.prefix(4), id: \.id) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                model.openActiveWorkItem(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(item.printerName) / \(item.paperName)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(workflowStageDisplayTitle(item.stage))
                                        .font(AppTypography.activeWorkStage)
                                        .foregroundStyle(.secondary)
                                    Text("Next: \(workflowNextActionDisplayTitle(stage: item.stage, rawTitle: item.nextAction))")
                                        .font(AppTypography.activeWorkSupporting)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(SurfaceRowButtonStyle(cornerRadius: 8))

                            Button(role: .destructive) {
                                model.requestActiveWorkDeletion(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(IconActionButtonStyle(size: 30, tone: .destructive))
                            .accessibilityLabel(ActiveWorkCopy.deleteAccessibilityLabel(for: item.title, jobId: item.id))
                            .accessibilityHint(ActiveWorkCopy.deleteHint)
                            .help(ActiveWorkCopy.deleteActionTitle)
                        }
                    }
                }
            }
        }
    }

    private var profileHealthPanel: some View {
        dashboardPanel(
            title: "Profile Health",
            subtitle: "Recent Printer Profiles stay separate from active jobs."
        ) {
            if model.printerProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    dashboardEmptyState("Published Printer Profiles will appear here with verification and print-setting context.")

                    Button("Open Printer Profiles") {
                        model.selectRoute(.printerProfiles)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.printerProfiles.prefix(3), id: \.id) { profile in
                        Button {
                            model.openPrinterProfile(profile)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(profile.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(profile.contextStatus)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(profile.printerName) / \(profile.paperName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text("Result: \(profile.result)")
                                    .font(AppTypography.trustSummarySupporting)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(SurfaceRowButtonStyle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var readinessPanel: some View {
        dashboardPanel(
            title: "Readiness",
            subtitle: "Check toolchain, app, and instrument status before starting measured work."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                readinessRow(title: "ArgyllCMS", value: model.argyllStatusLabel, tone: model.toolchainTone)
                readinessRow(title: "App", value: model.readinessLabel, tone: model.readinessTone)
                readinessRow(title: "Instrument", value: model.instrumentStatusLabel, tone: model.instrumentStatusTone)

                if let appHealth = model.appHealth {
                    let issues = Array(appHealth.blockingIssues.prefix(2))
                    let warnings = Array(appHealth.warnings.prefix(2))

                    if !issues.isEmpty || !warnings.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(issues, id: \.self) { issue in
                                readinessMessage(issue, systemImage: "xmark.octagon", tone: .blocked)
                            }

                            ForEach(warnings, id: \.self) { warning in
                                readinessMessage(warning, systemImage: "exclamationmark.triangle", tone: .attention)
                            }
                        }
                    }
                }
            }
        }
    }

    private func launcherButton(
        action: LauncherAction,
        symbolName: String,
        tone: StatusBadgeView.Tone,
        isCompact: Bool = false
    ) -> some View {
        Button {
            open(action)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(isCompact ? .title3 : .title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(action.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        StatusBadgeView(title: action.status, tone: tone)
                    }

                    Text(action.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(isCompact ? 3 : 2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 92 : 82, alignment: .topLeading)
        }
        .buttonStyle(SurfaceRowButtonStyle(cornerRadius: 8, horizontalPadding: 14, verticalPadding: 14))
    }

    private func readinessRow(title: String, value: String, tone: StatusBadgeView.Tone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.headline)
            Spacer()
            StatusBadgeView(title: value, tone: tone)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func readinessMessage(_ message: String, systemImage: String, tone: StatusBadgeView.Tone) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.foregroundColor)
                .frame(width: 16)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dashboardPanel<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            content()
        }
        .padding(18)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func dashboardEmptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func symbolName(for action: LauncherAction) -> String {
        switch action.kind {
        case .route(.inspect):
            return "waveform.path.ecg"
        case .route(.blackAndWhiteTuning):
            return "circle.lefthalf.filled"
        case .route(.troubleshoot):
            return "stethoscope"
        case .newProfile:
            return "plus.circle.fill"
        case .route, .planned:
            return "square.grid.2x2"
        }
    }

    private func open(_ action: LauncherAction) {
        switch action.kind {
        case .newProfile:
            Task { await model.openNewProfileWorkflow() }
        case let .route(route):
            model.selectRoute(route)
        case .planned:
            break
        }
    }
}
