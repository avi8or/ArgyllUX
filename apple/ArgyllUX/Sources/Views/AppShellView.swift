import SwiftUI

struct AppShellView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppModel
    @State private var isShowingErrorLogViewer = false
    @State private var isShowingJumpSheet = false
    @State private var isShowingInspectorSheet = false

    var body: some View {
        let chrome = model.shellChromeConfiguration

        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let showsInspectorFallback = ShellInspectorPresentation.showsInspectorFallback(
                for: chrome,
                availableWidth: availableWidth
            )

            VStack(spacing: 0) {
                topStrip(showsInspectorFallback: showsInspectorFallback)
                Divider()

                contentRow(for: chrome, availableWidth: availableWidth)

                if model.showsActiveWorkDock {
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
                }

                if chrome.showsFooterStatusBar {
                    Divider()

                    FooterStatusBarView(
                        argylluxVersion: model.argylluxVersionLabel,
                        argyllVersion: model.argyllVersionLabel,
                        toolchainStatusLabel: model.argyllStatusLabel,
                        toolchainTone: model.toolchainTone,
                        appReadinessLabel: model.readinessLabel,
                        appReadinessTone: model.readinessTone,
                        instrumentStatusLabel: model.instrumentStatusLabel,
                        instrumentTone: model.instrumentStatusTone,
                        lastValidationLabel: model.lastValidationLabel,
                        isRefreshing: model.isRefreshing,
                        onOpenCliTranscript: {
                            openWindow(id: CliTranscriptWindowView.windowID)
                            Task { await model.openLatestCliTranscript() }
                        },
                        onOpenErrorLogs: {
                            isShowingErrorLogViewer = true
                        }
                    )
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.bootstrapIfNeeded()
        }
        .sheet(isPresented: $isShowingErrorLogViewer) {
            LogViewerSheetView(model: model, kind: .error)
        }
        .sheet(isPresented: $isShowingJumpSheet) {
            ShellJumpSheetView(items: model.shellJumpItems) { item in
                model.openJumpItem(item)
                isShowingJumpSheet = false
            }
        }
        .sheet(isPresented: $isShowingInspectorSheet) {
            ShellInspectorSheetView(content: currentInspectorContent)
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
                model.confirmPendingDeletion()
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

    private func topStrip(showsInspectorFallback: Bool) -> some View {
        HStack(spacing: 12) {
            brandPlate

            ForEach(AppRoute.allCases) { route in
                Button {
                    model.selectRoute(route)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: route.symbolName)
                            .imageScale(.medium)
                        Text(route.title)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(
                        isRouteHighlighted(route)
                            ? AppTypography.shellNavigation.weight(.semibold)
                            : AppTypography.shellNavigation
                    )
                }
                .buttonStyle(ShellNavigationButtonStyle(isSelected: isRouteHighlighted(route)))
            }

            Spacer()

            Button {
                isShowingJumpSheet = true
            } label: {
                Label("Jump", systemImage: "magnifyingglass")
            }
            .buttonStyle(ShellNavigationButtonStyle(isSelected: false))
            .keyboardShortcut("k", modifiers: [.command])
            .help("Jump to routes, active jobs, profiles, printers, or papers.")

            if showsInspectorFallback {
                Button {
                    isShowingInspectorSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sidebar.right")
                            .imageScale(.medium)
                        Text("Guidance")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(ShellNavigationButtonStyle(isSelected: isShowingInspectorSheet))
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("Open Recommended, Advanced, and Technical guidance.")
                .accessibilityLabel("Open guidance inspector")
            }

            utilityPill(title: model.instrumentStatusLabel, systemImage: "scope")
            utilityPill(title: "Jobs \(model.jobsCount)", systemImage: "clock")
            utilityPill(title: "Alerts \(model.alertsCount)", systemImage: "exclamationmark.triangle")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var brandPlate: some View {
        Image("ArgyllUXMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 44, height: 44)
            .accessibilityLabel("ArgyllUX")
    }

    private func contentRow(for chrome: ShellChromeConfiguration, availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            currentRouteSurface(for: chrome)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if ShellInspectorPresentation.showsRightInspector(for: chrome, availableWidth: availableWidth) {
                Divider()

                InspectorView(content: currentInspectorContent)
                    .frame(width: ShellInspectorPresentation.rightInspectorWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func currentRouteSurface(for chrome: ShellChromeConfiguration) -> some View {
        switch chrome.routeAccessory {
        case .none, .workflowManaged:
            currentRouteView
        }
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
                RouteEntryView(route: model.selectedRoute)
            }
        }
    }

    private var currentInspectorContent: InspectorContent {
        if model.isShowingNewProfileWorkflow {
            guard let detail = model.activeNewProfileDetail else {
                return InspectorContent.openingWorkflow(
                    appHealth: model.appHealth,
                    toolchainStatus: model.toolchainStatus
                )
            }

            return InspectorContent.workflow(
                workflow: model.workflow,
                detail: detail,
                appHealth: model.appHealth,
                toolchainStatus: model.toolchainStatus
            )
        }

        return InspectorContent.route(
            route: model.selectedRoute,
            appHealth: model.appHealth,
            toolchainStatus: model.toolchainStatus
        )
    }

    private func utilityPill(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(AppTypography.shellUtility)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
    }

    private func isRouteHighlighted(_ route: AppRoute) -> Bool {
        if model.isShowingNewProfileWorkflow {
            return route == .home
        }

        return model.selectedRoute == route
    }
}

enum ShellInspectorPresentation {
    static let rightInspectorWidth: CGFloat = 320
    static let minimumWidthForRightInspector: CGFloat = 1180

    static func showsRightInspector(
        for chrome: ShellChromeConfiguration,
        availableWidth: CGFloat
    ) -> Bool {
        chrome.showsRightInspector && availableWidth >= minimumWidthForRightInspector
    }

    static func showsInspectorFallback(
        for chrome: ShellChromeConfiguration,
        availableWidth: CGFloat
    ) -> Bool {
        chrome.showsRightInspector && !showsRightInspector(for: chrome, availableWidth: availableWidth)
    }
}

private struct ShellInspectorSheetView: View {
    let content: InspectorContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("Guidance", systemImage: "sidebar.right")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            InspectorView(content: content)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 620)
    }
}

private struct ShellJumpSheetView: View {
    let items: [ShellJumpItem]
    let onSelect: (ShellJumpItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredItems: [ShellJumpItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return items }
        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                item.subtitle.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Jump")
                        .font(.title2.weight(.semibold))
                    Text("Open a route, active job, profile, printer, or paper.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(24)

            Divider()

            if filteredItems.isEmpty {
                Text("No matching destinations.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredItems) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: item.systemImage)
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(item.subtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(SurfaceRowButtonStyle(cornerRadius: 8))
                        }
                    }
                    .padding(24)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.regularMaterial)
        }
        .frame(minWidth: 560, minHeight: 520)
    }
}
