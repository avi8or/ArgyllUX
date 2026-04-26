import SwiftUI

struct PrinterProfilesView: View {
    @ObservedObject var library: ProfileLibraryModel
    let onRevealPath: (String) -> Void
    let onOpenJob: (String) -> Void
    let onRequestDeletion: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Printer Profiles")
                    .font(.largeTitle.weight(.semibold))

                if library.printerProfiles.isEmpty {
                    Text("Publish a New Profile to populate the library.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(library.printerProfiles, id: \.id) { profile in
                                Button {
                                    library.selectProfile(profile)
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
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(
                                    SurfaceRowButtonStyle(
                                        isSelected: library.selectedPrinterProfileID == profile.id,
                                        cornerRadius: 8,
                                        horizontalPadding: 14,
                                        verticalPadding: 10
                                    )
                                )
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
                    if let profile = library.selectedPrinterProfile {
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
                                onRevealPath(profile.profilePath)
                            }

                            Button("Reveal Measurement") {
                                onRevealPath(profile.measurementPath)
                            }

                            Button("Open Job") {
                                onOpenJob(profile.createdFromJobId)
                            }

                            Button(PrinterProfileCopy.deleteActionTitle, role: .destructive) {
                                onRequestDeletion()
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
