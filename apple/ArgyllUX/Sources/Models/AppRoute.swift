import Foundation

enum AppRoute: String, CaseIterable, Identifiable {
    case home
    case printerProfiles
    case troubleshoot
    case inspect
    case blackAndWhiteTuning
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            "Home"
        case .printerProfiles:
            "Printer Profiles"
        case .troubleshoot:
            "Troubleshoot"
        case .inspect:
            "Inspect"
        case .blackAndWhiteTuning:
            "B&W Tuning"
        case .settings:
            "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .home:
            "house"
        case .printerProfiles:
            "printer"
        case .troubleshoot:
            "stethoscope"
        case .inspect:
            "waveform.path.ecg"
        case .blackAndWhiteTuning:
            "circle.lefthalf.filled"
        case .settings:
            "gearshape"
        }
    }

    var placeholderSummary: String {
        switch self {
        case .home, .settings:
            ""
        case .printerProfiles:
            "This library locks the profile-first navigation shape for the next milestone."
        case .troubleshoot:
            "This route is reserved for Issue Cases, evidence review, and next-action guidance."
        case .inspect:
            "This analysis space will hold measurements, gamuts, and profiles without becoming a second workflow menu."
        case .blackAndWhiteTuning:
            "This route stays dedicated to monochrome tuning, neutrality checks, and validation history."
        }
    }

    var placeholderSections: [String] {
        switch self {
        case .home:
            []
        case .printerProfiles:
            ["Profile Library", "Verification Summary", "Linked Measurements"]
        case .troubleshoot:
            ["Issue Cases", "Evidence", "Recommended Next Actions"]
        case .inspect:
            ["Measurements", "Gamuts", "Profiles"]
        case .blackAndWhiteTuning:
            ["Current Path", "Neutrality Summary", "Validation History"]
        case .settings:
            ["Printers", "Papers", "Argyll", "Storage", "Defaults"]
        }
    }

    var inspectorNote: String {
        switch self {
        case .home:
            "Keep the operational overview honest. Health belongs in the shell before workflow depth exists."
        case .printerProfiles:
            "The library stays profile-first, with context supporting the profile instead of replacing it."
        case .troubleshoot:
            "Troubleshoot answers what to do next. Inspect answers what the evidence looks like."
        case .inspect:
            "Inspect stays analytical. It should not drift into diagnosis language."
        case .blackAndWhiteTuning:
            "B&W Tuning stays explicit about neutrality and tonal behavior rather than promising a generic profile flow."
        case .settings:
            "Settings owns support objects and toolchain configuration, not front-door workflow nouns."
        }
    }
}
