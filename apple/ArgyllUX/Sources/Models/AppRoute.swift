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

    var jumpSubtitle: String {
        switch self {
        case .home:
            "Operational overview"
        case .printerProfiles:
            "Profile library and trust summaries"
        case .troubleshoot:
            "Symptom-first diagnosis"
        case .inspect:
            "Measurement, gamut, and profile analysis"
        case .blackAndWhiteTuning:
            "Monochrome tuning and validation"
        case .settings:
            "Printers, papers, Argyll, storage, and defaults"
        }
    }

    var inspectorNote: String {
        switch self {
        case .home:
            "Start or resume work from here. Use the active-work dock for jobs that already have a next step."
        case .printerProfiles:
            "Review whether a profile is trustworthy before improving, rebuilding, or using it as a reference."
        case .troubleshoot:
            "Start with the visible print problem, then attach evidence before choosing a follow-up workflow."
        case .inspect:
            "Use Inspect when you want to understand measurements, gamuts, or profile internals without starting a repair flow."
        case .blackAndWhiteTuning:
            "Use this space for monochrome neutrality, tonal smoothness, and validation history."
        case .settings:
            "Create reusable printers, papers, print-path settings, and correct the Argyll installation here."
        }
    }

    var advancedInspectorNote: String {
        switch self {
        case .home:
            "Use Home for launch and resume decisions. Keep detailed setup in the route that owns the work."
        case .printerProfiles:
            "A profile is useful only with context: printer, paper, print settings, verification, and linked measurements."
        case .troubleshoot:
            "Evidence should come before repair. Start with symptoms, then link measurements or profiles when those surfaces are available."
        case .inspect:
            "Inspect is for analysis and comparison. It should not choose a fix without a troubleshooting case or workflow context."
        case .blackAndWhiteTuning:
            "B&W tuning may produce correction assets and validation results, not always a conventional ICC profile."
        case .settings:
            "Settings changes reusable support records. Workflows should reference those records instead of duplicating assumptions."
        }
    }
}
