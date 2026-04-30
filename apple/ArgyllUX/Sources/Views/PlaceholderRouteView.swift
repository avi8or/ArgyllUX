import SwiftUI

struct RouteEntryView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .troubleshoot:
            TroubleshootEntryRouteView()
        case .inspect:
            InspectEntryRouteView()
        case .blackAndWhiteTuning:
            BlackAndWhiteTuningEntryRouteView()
        case .home, .printerProfiles, .settings:
            RouteEntryScaffold(
                title: route.title,
                subtitle: route.jumpSubtitle
            ) {
                EmptyRouteState(
                    title: "Open this from the main navigation.",
                    message: "Use Home or Jump to return to the active surface."
                )
            }
        }
    }
}

private struct TroubleshootEntryRouteView: View {
    @State private var symptomDescription = ""

    private let symptoms = [
        "Neutrals are off",
        "A color family is wrong",
        "Prints are too dark or light",
        "B&W has a cast",
        "This setup used to be good",
        "Verification failed",
        "This paper never looks right",
        "Measurement problem",
    ]

    var body: some View {
        RouteEntryScaffold(
            title: "Troubleshoot",
            subtitle: "Start with what looks wrong, then gather evidence before choosing a fix."
        ) {
            HStack(alignment: .top, spacing: 18) {
                RouteSection("What looks wrong?") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Describe the visible print problem", text: $symptomDescription, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(4 ... 7)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], alignment: .leading, spacing: 10) {
                            ForEach(symptoms, id: \.self) { symptom in
                                Button(symptom) {
                                    symptomDescription = symptom
                                }
                                .buttonStyle(SymptomChipButtonStyle())
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 18) {
                    RouteSection("Evidence to Gather") {
                        VStack(alignment: .leading, spacing: 10) {
                            RouteGuidanceRow(
                                title: "Current Printer Profile",
                                message: "Link the profile used for the print so the app can compare the problem against the right printer, paper, and settings."
                            )
                            RouteGuidanceRow(
                                title: "Measurements",
                                message: "Use fresh measurements when the problem may be drift, media change, or target-reading error."
                            )
                            RouteGuidanceRow(
                                title: "Print Example",
                                message: "Keep a visible sample or reference image nearby so symptoms stay tied to output, not assumptions."
                            )
                        }
                    }

                    EmptyRouteState(
                        title: "Next step: collect evidence.",
                        message: "After identifying the symptom, open the relevant profile or measurement data to decide whether verification, improvement, or rebuild is the safest path."
                    )
                }
                .frame(width: 360, alignment: .topLeading)
            }
        }
    }
}

private struct InspectEntryRouteView: View {
    @State private var selectedSection: InspectSection = .measurements

    var body: some View {
        RouteEntryScaffold(
            title: "Inspect",
            subtitle: "Analyze measurements, gamuts, and profiles without starting a repair flow."
        ) {
            HStack(alignment: .top, spacing: 18) {
                RouteSidebarSection(title: "Inspect") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(InspectSection.allCases) { section in
                            Button {
                                selectedSection = section
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(section.title)
                                        .font(.headline)
                                    Text(section.sidebarSummary)
                                        .font(AppTypography.readableMetadata)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(SurfaceRowButtonStyle(isSelected: selectedSection == section, cornerRadius: 8))
                        }
                    }
                }
                .frame(width: 260, alignment: .topLeading)

                RouteSection(selectedSection.title) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selectedSection.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                            ForEach(selectedSection.focusAreas) { area in
                                RouteGuidanceRow(title: area.title, message: area.message)
                            }
                        }

                        EmptyRouteState(
                            title: selectedSection.emptyStateTitle,
                            message: selectedSection.emptyStateMessage
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct BlackAndWhiteTuningEntryRouteView: View {
    var body: some View {
        RouteEntryScaffold(
            title: "B&W Tuning",
            subtitle: "Track monochrome neutrality, tonal smoothness, and validation history."
        ) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    RouteSection("Current Path") {
                        EmptyRouteState(
                            title: "Choose the printer and paper path first.",
                            message: "B&W tuning depends on the exact printer, paper, media setting, quality mode, and monochrome path used for output."
                        )
                    }

                    RouteSection("Status") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 10) {
                            SummaryTile(title: "Neutrality", value: "No validation yet")
                            SummaryTile(title: "Smoothness", value: "No wedge measured")
                            SummaryTile(title: "History", value: "No linked runs")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                RouteSection("Path Checklist") {
                    VStack(alignment: .leading, spacing: 10) {
                        RouteGuidanceRow(
                            title: "Confirm settings",
                            message: "Use the same printer, paper, media setting, quality mode, and monochrome driver path every time."
                        )
                        RouteGuidanceRow(
                            title: "Print a neutral wedge",
                            message: "A neutral ramp reveals casts and tonal bumps that may not show in a color target."
                        )
                        RouteGuidanceRow(
                            title: "Measure and compare",
                            message: "Use measurements to separate visual preference from measurable neutrality and smoothness."
                        )
                    }
                }
                .frame(width: 360, alignment: .topLeading)
            }
        }
    }
}

private struct InspectFocusArea: Identifiable, Hashable {
    let title: String
    let message: String

    var id: String { title }
}

private enum InspectSection: String, CaseIterable, Identifiable {
    case measurements
    case gamuts
    case profiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .measurements:
            "Measurements"
        case .gamuts:
            "Gamuts"
        case .profiles:
            "Profiles"
        }
    }

    var sidebarSummary: String {
        switch self {
        case .measurements:
            "Patch reads and drift"
        case .gamuts:
            "Output range and overlap"
        case .profiles:
            "Profile internals"
        }
    }

    var summary: String {
        switch self {
        case .measurements:
            "Review measurement files, compare measured output to targets, and look for drift before deciding on a repair path."
        case .gamuts:
            "Compare output gamuts and identify likely clipping or overlap between profile conditions."
        case .profiles:
            "Inspect profile internals, neutral-axis behavior, black generation, and linked artifacts."
        }
    }

    var focusAreas: [InspectFocusArea] {
        switch self {
        case .measurements:
            [
                InspectFocusArea(title: "Spot Measure", message: "Check a single color or neutral sample against a known reference."),
                InspectFocusArea(title: "Compare Measurements", message: "Look for drift between current readings and a trusted baseline."),
                InspectFocusArea(title: "Measured vs Target", message: "Find patches where output diverges from the intended target."),
                InspectFocusArea(title: "Worst Patches", message: "Prioritize the largest errors before choosing a fix."),
            ]
        case .gamuts:
            [
                InspectFocusArea(title: "Single Profile Gamut", message: "Understand the usable range for one printer and paper condition."),
                InspectFocusArea(title: "Profile Comparison", message: "Compare two output conditions without turning the view into a repair recommendation."),
                InspectFocusArea(title: "Image vs Output Gamut", message: "Check whether important image colors fit the selected output condition."),
                InspectFocusArea(title: "Clipping Regions", message: "Identify where colors are likely to compress or clip."),
            ]
        case .profiles:
            [
                InspectFocusArea(title: "Overview", message: "Review identity, profile class, and linked artifacts."),
                InspectFocusArea(title: "Internals", message: "Inspect technical profile tags and generation metadata."),
                InspectFocusArea(title: "Neutral Axis", message: "Check whether grays stay stable through the profile."),
                InspectFocusArea(title: "Black Generation", message: "Review black behavior when the profile exposes useful data."),
            ]
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .measurements:
            "Open or import measurement data to inspect readings."
        case .gamuts:
            "Choose one or more profiles to inspect gamut behavior."
        case .profiles:
            "Select a Printer Profile to inspect technical details."
        }
    }

    var emptyStateMessage: String {
        switch self {
        case .measurements:
            "Measurement analysis starts from CGATS data, spot reads, or a New Profile job with measured output."
        case .gamuts:
            "Gamut views need a profile or comparison pair so the graph can stay tied to a real output condition."
        case .profiles:
            "Profile inspection stays separate from repair recommendations; use Troubleshoot when the goal is choosing a fix."
        }
    }
}

private struct RouteEntryScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width < 900 {
                ScrollView {
                    routeContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                routeContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var routeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct RouteSection<Content: View>: View {
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

private struct RouteSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RouteGuidanceRow: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyRouteState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.45))
                .frame(width: 3)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(AppTypography.trustSummarySupporting)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SymptomChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.statusBadge)
            .foregroundStyle(configuration.isPressed ? .primary : .secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.secondary.opacity(configuration.isPressed ? 0.22 : 0.12), lineWidth: 1)
            }
    }
}
