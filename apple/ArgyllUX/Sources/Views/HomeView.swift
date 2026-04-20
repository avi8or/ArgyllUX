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
                            .disabled(true)
                        }
                    }
                    Text("This foundation pass locks the action language and layout before workflow launchers go live.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                section("Active work") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.activeWorkItems) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.headline)
                                Text("Next: \(item.nextAction)")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                section("Profile health") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.profileHealthItems) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.context)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(item.result)
                                    .font(.subheadline)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                section("Toolchain and app health") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            StatusBadgeView(title: model.argyllStatusLabel, tone: toolchainTone)
                            StatusBadgeView(title: model.readinessLabel, tone: readinessTone)
                            if model.isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        detailRow(title: "Detected path", value: model.detectedToolchainPath)
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
}
