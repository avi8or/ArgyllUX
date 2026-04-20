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
            ActiveWorkCopy.deleteActionTitle,
            isPresented: Binding(
                get: { model.activeWorkDeletionJobID != nil },
                set: { isPresented in
                    if !isPresented {
                        model.cancelActiveWorkDeletion()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(ActiveWorkCopy.deleteActionTitle, role: .destructive) {
                Task { await model.confirmActiveWorkDeletion() }
            }

            Button("Cancel", role: .cancel) {
                model.cancelActiveWorkDeletion()
            }
        } message: {
            Text(deletionConfirmationMessage)
        }
        .alert(
            ActiveWorkCopy.deleteErrorTitle,
            isPresented: Binding(
                get: { model.activeWorkDeletionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.clearActiveWorkDeletionError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.clearActiveWorkDeletionError()
            }
        } message: {
            Text(model.activeWorkDeletionErrorMessage ?? "")
        }
    }

    private var deletionConfirmationMessage: String {
        ActiveWorkCopy.deletionConfirmationMessage(jobTitle: model.activeWorkDeletionJobTitle)
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
            NewProfileWorkflowView(model: model)
        } else {
            switch model.selectedRoute {
            case .home:
                HomeView(model: model)
            case .settings:
                SettingsView(model: model)
            case .printerProfiles:
                PrinterProfilesView(model: model)
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

struct PrinterProfilesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Printer Profiles")
                    .font(.largeTitle.weight(.semibold))

                if model.printerProfiles.isEmpty {
                    Text("Publish a New Profile to populate the library.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.printerProfiles, id: \.id) { profile in
                                Button {
                                    model.selectedPrinterProfileID = profile.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
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
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        model.selectedPrinterProfileID == profile.id
                                            ? Color.accentColor.opacity(0.14)
                                            : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(width: 320, alignment: .topLeading)
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let profile = model.selectedPrinterProfile {
                        Text(profile.name)
                            .font(.title.weight(.semibold))

                        OperationalDetailRow(title: "Printer", value: profile.printerName)
                        OperationalDetailRow(title: "Paper", value: profile.paperName)
                        OperationalDetailRow(title: "Result", value: profile.result)
                        OperationalDetailRow(title: "Print settings", value: profile.printSettings)
                        OperationalDetailRow(title: "Verified against file", value: profile.verifiedAgainstFile)
                        OperationalDetailRow(
                            title: "Last verification date",
                            value: profile.lastVerificationDate ?? "Not yet verified"
                        )
                        OperationalDetailRow(title: "ICC path", value: profile.profilePath)
                        OperationalDetailRow(title: "Measurement path", value: profile.measurementPath)
                        OperationalDetailRow(title: "Context", value: profile.contextStatus)
                        OperationalDetailRow(title: "Created from job", value: profile.createdFromJobId)

                        HStack(spacing: 10) {
                            Button("Reveal ICC") {
                                model.revealPathInFinder(profile.profilePath)
                            }

                            Button("Reveal Measurement") {
                                model.revealPathInFinder(profile.measurementPath)
                            }

                            Button("Open Job") {
                                model.openNewProfileJob(jobId: profile.createdFromJobId)
                            }
                        }
                    } else {
                        Text("Select a Printer Profile.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
