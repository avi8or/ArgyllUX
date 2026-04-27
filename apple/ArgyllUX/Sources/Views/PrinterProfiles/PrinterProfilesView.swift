import SwiftUI

struct PrinterProfilesView: View {
    @ObservedObject var library: ProfileLibraryModel
    let onRevealPath: (String) -> Void
    let onOpenJob: (String) -> Void
    let onRequestDeletion: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            profileList
                .frame(width: 340, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding(24)

            Divider()

            profileDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Printer Profiles")
                    .font(.largeTitle.weight(.semibold))
                Text("Browse profiles by trust, context, and recent verification.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if library.printerProfiles.isEmpty {
                EmptyProfileLibraryView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(library.printerProfiles, id: \.id) { profile in
                            Button {
                                library.selectProfile(profile)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
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

                                    Text("Last verification date: \(profile.lastVerificationDate ?? "Not yet verified")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(
                                SurfaceRowButtonStyle(
                                    isSelected: library.selectedPrinterProfileID == profile.id,
                                    cornerRadius: 8,
                                    horizontalPadding: 14,
                                    verticalPadding: 12
                                )
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var profileDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let profile = library.selectedPrinterProfile {
                    ProfileTrustHeader(profile: profile)

                    ProfileDetailSection("Verification Summary") {
                        LazyVGrid(columns: detailColumns, alignment: .leading, spacing: 12) {
                            SummaryTile(title: "Result", value: profile.result)
                            SummaryTile(title: "Last verification date", value: profile.lastVerificationDate ?? "Not yet verified")
                            SummaryTile(title: "Verified against file", value: profile.verifiedAgainstFile)
                            SummaryTile(title: "Print settings", value: profile.printSettings)
                        }
                    }

                    ProfileDetailSection("Context") {
                        LazyVGrid(columns: detailColumns, alignment: .leading, spacing: 12) {
                            OperationalDetailRow(title: "Printer", value: profile.printerName)
                            OperationalDetailRow(title: "Paper", value: profile.paperName)
                            OperationalDetailRow(title: "Context status", value: profile.contextStatus)
                            OperationalDetailRow(title: "Created from job", value: profile.createdFromJobId)
                        }
                    }

                    ProfileDetailSection("Actions") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], alignment: .leading, spacing: 10) {
                            Button("Open Job") {
                                onOpenJob(profile.createdFromJobId)
                            }
                            .buttonStyle(.borderedProminent)

                            PlannedActionSurface(descriptor: plannedProfileAction("Improve Profile"), minimumHeight: 36)
                            PlannedActionSurface(descriptor: plannedProfileAction("Verify Output"), minimumHeight: 36)
                            PlannedActionSurface(descriptor: plannedProfileAction("Recalibrate"), minimumHeight: 36)
                            PlannedActionSurface(descriptor: plannedProfileAction("Rebuild"), minimumHeight: 36)
                            PlannedActionSurface(descriptor: plannedProfileAction("Match a Reference"), minimumHeight: 36)
                            PlannedActionSurface(descriptor: plannedProfileAction("Inspect Measurements"), minimumHeight: 36)
                            PlannedActionSurface(descriptor: plannedProfileAction("Inspect Gamut"), minimumHeight: 36)
                            PlannedActionSurface(descriptor: plannedProfileAction("Inspect Profile"), minimumHeight: 36)
                        }
                    }

                    ProfileDetailSection("Linked Artifacts") {
                        VStack(alignment: .leading, spacing: 12) {
                            ArtifactRow(title: "ICC profile", path: profile.profilePath, onReveal: onRevealPath)
                            ArtifactRow(title: "Measurements", path: profile.measurementPath, onReveal: onRevealPath)
                        }
                    }

                    ProfileDetailSection("Library Management") {
                        Button(PrinterProfileCopy.deleteActionTitle, role: .destructive) {
                            onRequestDeletion()
                        }
                    }
                } else {
                    EmptyProfileLibraryView(message: "Select a Printer Profile to review trust, context, and linked measurements.")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var detailColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 210), spacing: 12)]
    }

    private func plannedProfileAction(_ title: String) -> PlannedActionDescriptor {
        PlannedActionDescriptor(
            title: title,
            message: "\(title) is planned for Printer Profiles. Not runnable in this build."
        )
    }
}

private struct ProfileTrustHeader: View {
    let profile: PrinterProfileRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(profile.name)
                    .font(.title.weight(.semibold))
                Text(profile.contextStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            }

            Text("\(profile.printerName) / \(profile.paperName)")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Use this view to decide whether the profile is still trustworthy before improving, rebuilding, or using it as a reference.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProfileDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            content()
        }
        .padding(18)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ArtifactRow: View {
    let title: String
    let path: String
    let onReveal: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(path)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button("Reveal") {
                onReveal(path)
            }
            .buttonStyle(FooterLinkButtonStyle())
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyProfileLibraryView: View {
    var message = "Publish a New Profile to populate the library."

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
