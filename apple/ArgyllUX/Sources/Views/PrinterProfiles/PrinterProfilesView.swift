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
                                        MetadataPillView(title: profile.contextStatus)
                                    }

                                    Text("\(profile.printerName) / \(profile.paperName)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)

                                    Text("Result: \(profile.result)")
                                        .font(AppTypography.trustSummarySupporting)
                                        .foregroundStyle(.secondary)

                                    Text("Last verification date: \(profile.lastVerificationDate ?? "Not yet verified")")
                                        .font(AppTypography.readableMetadata)
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

                    ProfileDetailSection("Recommended Next Action") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Open the source job to review how this profile was created, then decide whether the current output needs verification, repair, or a rebuild.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button("Open Source Job") {
                                onOpenJob(profile.createdFromJobId)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    ProfileDetailSection("Follow-up Guidance") {
                        VStack(alignment: .leading, spacing: 10) {
                            ProfileFollowUpRow(
                                title: "Verify Output",
                                message: "Use fresh evidence when the last verification is old or the print no longer matches expectations."
                            )
                            ProfileFollowUpRow(
                                title: "Improve Profile",
                                message: "Use when the printer, paper, and settings are still correct but better measurement data is available."
                            )
                            ProfileFollowUpRow(
                                title: "Rebuild",
                                message: "Use when printer, paper, driver, media setting, or calibration context has changed."
                            )
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
}

private struct ProfileFollowUpRow: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProfileTrustHeader: View {
    let profile: PrinterProfileRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(profile.name)
                        .font(.title.weight(.semibold))
                    MetadataPillView(title: profile.contextStatus)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.name)
                        .font(.title.weight(.semibold))
                    MetadataPillView(title: profile.contextStatus)
                }
            }

            Text("\(profile.printerName) / \(profile.paperName)")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Use this view to decide whether the profile is still trustworthy before improving, rebuilding, or using it as a reference.")
                .font(AppTypography.trustSummarySupporting)
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
                    .font(.system(.callout, design: .monospaced))
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
