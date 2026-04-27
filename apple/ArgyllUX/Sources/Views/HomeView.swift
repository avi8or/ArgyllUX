import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel

    private let launcherColumns = [
        GridItem(.flexible(minimum: 190), spacing: 10),
        GridItem(.flexible(minimum: 190), spacing: 10),
    ]

    private var routeActions: [LauncherAction] {
        model.availableLauncherActions.filter {
            if case .route = $0.kind {
                return true
            }
            return false
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if geometry.size.width < 1060 {
                        VStack(alignment: .leading, spacing: 18) {
                            primaryLauncherPanel
                            activeWorkPanel
                            profileHealthPanel
                            routeEntryPanel
                            plannedWorkPanel
                        }
                    } else {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 18) {
                                primaryLauncherPanel
                                routeEntryPanel
                                plannedWorkPanel
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                            VStack(alignment: .leading, spacing: 18) {
                                activeWorkPanel
                                profileHealthPanel
                            }
                            .frame(width: 380)
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Home")
                .font(.largeTitle.weight(.semibold))
            Text("Start new profiling work, resume active jobs, or check whether recent profiles are still trustworthy.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var primaryLauncherPanel: some View {
        dashboardPanel(
            title: "Start Work",
            subtitle: "Use goal-first actions. New Profile is the runnable profiling workflow in this build."
        ) {
            if let newProfileAction = model.availableLauncherActions.first(where: { $0.kind == .newProfile }) {
                Button {
                    Task { await model.openNewProfileWorkflow() }
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(newProfileAction.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                StatusBadgeView(title: newProfileAction.status, tone: .ready)
                            }
                            Text(newProfileAction.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                }
                .buttonStyle(SurfaceRowButtonStyle(cornerRadius: 8, horizontalPadding: 14, verticalPadding: 14))
            }
        }
    }

    private var routeEntryPanel: some View {
        dashboardPanel(
            title: "Open a Workspace",
            subtitle: "These routes are available as entry screens. They do not run the missing workflow engines yet."
        ) {
            LazyVGrid(columns: launcherColumns, alignment: .leading, spacing: 10) {
                ForEach(routeActions) { action in
                    Button {
                        open(action)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Text(action.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(action.status)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(action.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                    }
                    .buttonStyle(SurfaceRowButtonStyle(cornerRadius: 8))
                }
            }
        }
    }

    private var plannedWorkPanel: some View {
        dashboardPanel(
            title: "Planned Workflows",
            subtitle: "These actions are named now so the app language stays consistent. They are not runnable in this build."
        ) {
            LazyVGrid(columns: launcherColumns, alignment: .leading, spacing: 10) {
                ForEach(model.plannedLauncherActions) { action in
                    if let descriptor = action.plannedDescriptor {
                        PlannedActionSurface(descriptor: descriptor, minimumHeight: 76)
                    }
                }
            }
        }
    }

    private var activeWorkPanel: some View {
        dashboardPanel(
            title: "Active Work",
            subtitle: "Resume jobs that already have a next step."
        ) {
            if model.activeWorkItems.isEmpty {
                dashboardEmptyState(ActiveWorkCopy.emptyStateMessage)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.activeWorkItems.prefix(3), id: \.id) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                model.openActiveWorkItem(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
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
            subtitle: "Recent trust summaries are separate from active jobs."
        ) {
            if model.printerProfiles.isEmpty {
                dashboardEmptyState("Published Printer Profiles will appear here with verification and print-setting context.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.printerProfiles.prefix(3), id: \.id) { profile in
                        Button {
                            model.openPrinterProfile(profile)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(profile.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("\(profile.printerName) / \(profile.paperName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
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
