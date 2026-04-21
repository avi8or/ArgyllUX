import Foundation

/// Owns Printer Profiles library selection so shell routing does not have to
/// carry profile-list state inline with unrelated workflow/editor state.
@MainActor
final class ProfileLibraryModel: ObservableObject {
    @Published private(set) var printerProfiles: [PrinterProfileRecord] = []
    @Published var selectedPrinterProfileID: String?

    var selectedPrinterProfile: PrinterProfileRecord? {
        guard let selectedPrinterProfileID else { return printerProfiles.first }
        return printerProfiles.first { $0.id == selectedPrinterProfileID }
    }

    func applyReferenceData(_ data: AppReferenceData) {
        applyProfiles(data.printerProfiles)
    }

    func applyProfiles(_ profiles: [PrinterProfileRecord]) {
        printerProfiles = profiles

        if selectedPrinterProfileID == nil || !profiles.contains(where: { $0.id == selectedPrinterProfileID }) {
            selectedPrinterProfileID = profiles.first?.id
        }
    }

    func selectProfile(_ profile: PrinterProfileRecord) {
        selectedPrinterProfileID = profile.id
    }

    func selectProfile(id: String?) {
        selectedPrinterProfileID = id
    }
}
