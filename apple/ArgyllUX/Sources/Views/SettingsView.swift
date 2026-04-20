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
                    Text("Printer definitions land here next so the shell can stay profile-first.")
                        .foregroundStyle(.secondary)
                }

                settingsSection("Papers") {
                    Text("Paper presets and related defaults stay here rather than becoming a top-level library.")
                        .foregroundStyle(.secondary)
                }

                settingsSection("Defaults") {
                    Text("Application-wide defaults land here after the foundation pass.")
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

                        if !model.recentLogs.isEmpty {
                            Divider()

                            Text("Recent logs")
                                .font(.headline)

                            ForEach(model.recentLogs, id: \.timestamp) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(entry.level.uppercased()) • \(entry.source)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(entry.message)
                                        .font(.subheadline)
                                    Text(entry.timestamp)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
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
}
