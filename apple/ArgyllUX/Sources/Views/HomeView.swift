import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel

    private let launcherColumns = [
        GridItem(.flexible(minimum: 180), spacing: 10),
        GridItem(.flexible(minimum: 180), spacing: 10),
    ]

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Home")
                        .font(.largeTitle.weight(.semibold))

                    if geometry.size.width < 1040 {
                        VStack(alignment: .leading, spacing: 18) {
                            startTaskPanel
                            activeWorkPanel
                            profileHealthPanel
                        }
                    } else {
                        HStack(alignment: .top, spacing: 18) {
                            startTaskPanel
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            VStack(alignment: .leading, spacing: 18) {
                                activeWorkPanel
                                profileHealthPanel
                            }
                            .frame(width: 360)
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var startTaskPanel: some View {
        dashboardPanel(
            title: "Start a task",
            subtitle: "Goal-first launchers stay visible here. Only New Profile is active in the current slice."
        ) {
            LazyVGrid(columns: launcherColumns, alignment: .leading, spacing: 10) {
                ForEach(model.launcherActions) { action in
                    Button {
                        if action.kind == .newProfile {
                            Task { await model.openNewProfileWorkflow() }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(action.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(action.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                        .padding(12)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(action.kind != .newProfile)
                }
            }
        }
    }

    private var activeWorkPanel: some View {
        dashboardPanel(
            title: "Active work",
            subtitle: "This is a compact summary. The dock remains the persistent resume surface."
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(stageTitle(item.stage))
                                        .font(AppTypography.activeWorkStage)
                                        .foregroundStyle(.secondary)
                                    Text("Next: \(item.nextAction)")
                                        .font(AppTypography.activeWorkSupporting)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button(role: .destructive) {
                                model.requestActiveWorkDeletion(item)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ActiveWorkCopy.deleteAccessibilityLabel(for: item.title))
                            .help(ActiveWorkCopy.deleteActionTitle)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var profileHealthPanel: some View {
        dashboardPanel(
            title: "Profile health",
            subtitle: "Recent trust summaries stay separate from active jobs."
        ) {
            if model.printerProfiles.isEmpty {
                dashboardEmptyState("Publish a Printer Profile to populate trust summaries here.")
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
                                Text("\(profile.printerName) • \(profile.paperName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(profile.result)
                                    .font(AppTypography.trustSummarySupporting)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
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
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func dashboardEmptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
}
