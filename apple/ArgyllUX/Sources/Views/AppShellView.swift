import SwiftUI

struct AppShellView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppModel
    @State private var isShowingErrorLogViewer = false

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            Divider()

            HStack(spacing: 0) {
                currentRouteView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if !model.isShowingNewProfileWorkflow {
                    Divider()

                    InspectorView(
                        route: model.selectedRoute,
                        appHealth: model.appHealth,
                        toolchainStatus: model.toolchainStatus
                    )
                    .frame(width: 300)
                }
            }

            Divider()

            ActiveWorkDockView(
                items: model.activeWorkItems,
                onSelect: { item in
                    model.openActiveWorkItem(item)
                },
                onDelete: { item in
                    model.requestActiveWorkDeletion(item)
                }
            )

            Divider()

            FooterStatusBarView(
                argylluxVersion: model.argylluxVersionLabel,
                argyllVersion: model.argyllVersionLabel,
                instrumentStatusLabel: model.instrumentStatusLabel,
                onOpenCliTranscript: {
                    openWindow(id: CliTranscriptWindowView.windowID)
                    Task { await model.openLatestCliTranscript() }
                },
                onOpenErrorLogs: {
                    isShowingErrorLogViewer = true
                }
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.bootstrapIfNeeded()
        }
        .sheet(isPresented: $isShowingErrorLogViewer) {
            LogViewerSheetView(model: model, kind: .error)
        }
        .confirmationDialog(
            model.deletionConfirmationTitle,
            isPresented: Binding(
                get: { model.isShowingDeletionConfirmation },
                set: { isPresented in
                    if !isPresented {
                        model.cancelPendingDeletion()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(model.deletionConfirmationTitle, role: .destructive) {
                Task { await model.confirmPendingDeletion() }
            }

            Button("Cancel", role: .cancel) {
                model.cancelPendingDeletion()
            }
        } message: {
            Text(model.deletionConfirmationMessage)
        }
        .alert(
            model.deletionErrorTitle,
            isPresented: Binding(
                get: { model.isShowingDeletionError },
                set: { isPresented in
                    if !isPresented {
                        model.clearDeletionError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.clearDeletionError()
            }
        } message: {
            Text(model.deletionErrorMessage ?? "")
        }
    }

    private var topStrip: some View {
        HStack(spacing: 16) {
            Text("ArgyllUX")
                .font(.title3.weight(.semibold))

            ForEach(AppRoute.allCases) { route in
                Button {
                    model.selectRoute(route)
                } label: {
                    Label(route.title, systemImage: route.symbolName)
                        .labelStyle(.titleAndIcon)
                        .font(
                            isRouteHighlighted(route)
                                ? AppTypography.shellNavigation.weight(.semibold)
                                : AppTypography.shellNavigation
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            isRouteHighlighted(route)
                                ? Color.accentColor.opacity(0.14)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            utilityPill(title: "Search / Jump")
            utilityPill(title: model.instrumentStatusLabel)
            utilityPill(title: "Jobs \(model.jobsCount)")
            utilityPill(title: "Alerts \(model.alertsCount)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var currentRouteView: some View {
        if model.isShowingNewProfileWorkflow {
            NewProfileWorkflowView(
                workflow: model.workflow,
                transcript: model.cliTranscript,
                actions: NewProfileWorkflowActions(
                    performPrimaryAction: {
                        Task { await model.performWorkflowPrimaryAction() }
                    },
                    requestWorkflowDeletion: {
                        model.requestCurrentWorkflowDeletion()
                    },
                    openCliTranscript: { jobId in
                        openWindow(id: CliTranscriptWindowView.windowID)
                        Task { await model.openCliTranscript(jobId: jobId) }
                    },
                    saveContext: {
                        Task { await model.saveWorkflowContext() }
                    },
                    createWorkflowPrinter: {
                        Task { await model.createWorkflowPrinter() }
                    },
                    createWorkflowPaper: {
                        Task { await model.createWorkflowPaper() }
                    },
                    createWorkflowPreset: {
                        Task { await model.createWorkflowPreset() }
                    },
                    saveTargetSettings: {
                        Task { await model.saveTargetSettings() }
                    },
                    generateTarget: {
                        Task { await model.generateTarget() }
                    },
                    savePrintSettings: {
                        Task { await model.savePrintSettings() }
                    },
                    markChartPrinted: {
                        Task { await model.markChartPrinted() }
                    },
                    markReadyToMeasure: {
                        Task { await model.markReadyToMeasure() }
                    },
                    startMeasurement: {
                        Task { await model.startMeasurement() }
                    },
                    buildProfile: {
                        Task { await model.buildProfile() }
                    },
                    publishProfile: {
                        Task { await model.publishProfile() }
                    },
                    openPublishedProfileLibrary: {
                        model.openPublishedProfileLibrary()
                    }
                )
            )
        } else {
            switch model.selectedRoute {
            case .home:
                HomeView(model: model)
            case .settings:
                SettingsView(
                    settings: model.settings,
                    storagePaths: model.storagePaths,
                    appHealth: model.appHealth,
                    onApplyToolchainPath: {
                        Task { await model.applyToolchainPath() }
                    },
                    onRevalidateToolchain: {
                        Task { await model.revalidateToolchain() }
                    },
                    onClearToolchainOverride: {
                        Task { await model.clearToolchainOverride() }
                    },
                    onStartNewProfile: { printerId, paperId in
                        model.startNewProfileFromSettings(printerId: printerId, paperId: paperId)
                    },
                    onSavePrinter: {
                        Task { await model.saveSettingsPrinter() }
                    },
                    onSavePaper: {
                        Task { await model.saveSettingsPaper() }
                    },
                    onSavePreset: {
                        Task { await model.saveSettingsPreset() }
                    }
                )
            case .printerProfiles:
                PrinterProfilesView(
                    library: model.profileLibrary,
                    onRevealPath: model.revealPathInFinder,
                    onOpenJob: model.openNewProfileJob,
                    onRequestDeletion: model.requestSelectedPrinterProfileDeletion
                )
            case .troubleshoot, .inspect, .blackAndWhiteTuning:
                PlaceholderRouteView(route: model.selectedRoute)
            }
        }
    }

    private func utilityPill(title: String) -> some View {
        Text(title)
            .font(AppTypography.shellUtility)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    private func isRouteHighlighted(_ route: AppRoute) -> Bool {
        if model.isShowingNewProfileWorkflow {
            return route == .home
        }

        return model.selectedRoute == route
    }
}
