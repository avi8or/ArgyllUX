import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel

    private let gridColumns = [
        GridItem(.adaptive(minimum: 180), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Home")
                    .font(.largeTitle.weight(.semibold))

                section("Start a task") {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                        ForEach(model.launcherActions) { action in
                            Button {
                                if action.kind == .newProfile {
                                    Task { await model.openNewProfileWorkflow() }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(action.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(action.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                                .padding(14)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(action.kind != .newProfile)
                        }
                    }

                    Text("The vertical slice starts with New Profile. The other launchers stay visible so the shell language remains locked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                section("Active work") {
                    if model.activeWorkItems.isEmpty {
                        emptyState(ActiveWorkCopy.emptyStateMessage)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.activeWorkItems, id: \.id) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Button {
                                        model.openActiveWorkItem(item)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.title)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text(stageTitle(item.stage))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Text("Next: \(item.nextAction)")
                                                .foregroundStyle(.secondary)
                                            Text("\(item.printerName) | \(item.paperName)")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    Button(role: .destructive) {
                                        model.requestActiveWorkDeletion(item)
                                    } label: {
                                        Label(ActiveWorkCopy.deleteActionTitle, systemImage: "trash")
                                            .labelStyle(.iconOnly)
                                            .frame(width: 32, height: 32)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(ActiveWorkCopy.deleteAccessibilityLabel(for: item.title))
                                    .accessibilityHint(ActiveWorkCopy.deleteHint)
                                    .help(ActiveWorkCopy.deleteActionTitle)
                                }
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                section("Profile health") {
                    emptyState("Profile trust summaries land after the first real job flow exists.")
                }

                section("Toolchain and app health") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            StatusBadgeView(title: model.argyllStatusLabel, tone: toolchainTone)
                            StatusBadgeView(title: model.readinessLabel, tone: readinessTone)
                            StatusBadgeView(title: model.instrumentStatusLabel, tone: model.instrumentStatusTone)
                            if model.isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        detailRow(title: "Detected path", value: model.detectedToolchainPath)
                        detailRow(title: "ArgyllCMS version", value: model.argyllVersionLabel)
                        detailRow(title: "Last validation", value: model.lastValidationLabel)

                        if let appHealth = model.appHealth {
                            if !appHealth.blockingIssues.isEmpty {
                                detailList(title: "Blocking issues", items: appHealth.blockingIssues)
                            }
                            if !appHealth.warnings.isEmpty {
                                detailList(title: "Warnings", items: appHealth.warnings)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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

    private var readinessTone: StatusBadgeView.Tone {
        switch model.appHealth?.readiness {
        case "ready":
            .ready
        case "attention":
            .attention
        case "blocked", .none:
            .blocked
        default:
            .blocked
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            content()
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
