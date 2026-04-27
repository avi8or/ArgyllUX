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
                    title: "No content is ready here yet.",
                    message: "Use Home or Jump to open the current live surfaces."
                )
            }
        }
    }
}

private struct TroubleshootEntryRouteView: View {
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
            subtitle: "Start with what looks wrong, then attach evidence before choosing a fix."
        ) {
            RouteSection("What looks wrong?") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(symptoms, id: \.self) { symptom in
                        PlannedChipSurface(descriptor: plannedSymptomOption(symptom))
                    }
                }
            }

            RouteSection("Evidence") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], alignment: .leading, spacing: 10) {
                    PlannedActionSurface(descriptor: plannedRouteAction("Import Measurements"))
                    PlannedActionSurface(descriptor: plannedRouteAction("Use Existing Measurements"))
                    PlannedActionSurface(descriptor: plannedRouteAction("Link Current Profile"))
                    PlannedActionSurface(descriptor: plannedRouteAction("Add Notes"))
                }
            }

            EmptyRouteState(
                title: "Issue Cases are planned.",
                message: "This screen establishes the symptom-first shape without saving Issue Cases or running diagnosis yet."
            )
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
            Picker("Inspect section", selection: $selectedSection) {
                ForEach(InspectSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            RouteSection(selectedSection.title) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedSection.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(selectedSection.plannedViews, id: \.self) { plannedView in
                            PlannedActionSurface(descriptor: plannedRouteAction(plannedView))
                        }
                    }
                }
            }

            EmptyRouteState(
                title: "Analysis views are planned.",
                message: "Open a published profile or New Profile job for the live data currently available."
            )
        }
    }
}

private struct BlackAndWhiteTuningEntryRouteView: View {
    var body: some View {
        RouteEntryScaffold(
            title: "B&W Tuning",
            subtitle: "Track monochrome neutrality, tonal smoothness, and validation history."
        ) {
            RouteSection("Current Path") {
                EmptyRouteState(
                    title: "No monochrome path selected.",
                    message: "Saved printer and paper settings will provide the path context for B&W tuning."
                )
            }

            RouteSection("Status") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], alignment: .leading, spacing: 10) {
                    SummaryTile(title: "Neutrality", value: "No validation yet")
                    SummaryTile(title: "Smoothness", value: "No wedge measured")
                    SummaryTile(title: "History", value: "No linked runs")
                }
            }

            RouteSection("Actions") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], alignment: .leading, spacing: 10) {
                    PlannedActionSurface(descriptor: plannedRouteAction("Print Wedge"))
                    PlannedActionSurface(descriptor: plannedRouteAction("Measure Wedge"))
                    PlannedActionSurface(descriptor: plannedRouteAction("Validate Output"))
                    PlannedActionSurface(descriptor: plannedRouteAction("Open Issue Case"))
                }
            }
        }
    }
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

    var summary: String {
        switch self {
        case .measurements:
            "Review spot reads, CGATS tables, measured-vs-target results, and drift against a trusted baseline."
        case .gamuts:
            "Compare output gamuts and identify likely clipping or overlap between profile conditions."
        case .profiles:
            "Inspect profile internals, neutral-axis behavior, black generation, and raw tags."
        }
    }

    var plannedViews: [String] {
        switch self {
        case .measurements:
            ["Spot Measure", "Compare Measurements", "Measured vs Target", "Worst Patches"]
        case .gamuts:
            ["Single Profile Gamut", "Profile Comparison", "Image vs Output Gamut", "Clipping Regions"]
        case .profiles:
            ["Overview", "Internals", "Neutral Axis", "Black Generation"]
        }
    }
}

private struct RouteEntryScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private func plannedRouteAction(_ title: String) -> PlannedActionDescriptor {
    PlannedActionDescriptor(
        title: title,
        message: "\(title) is named for this workspace. Not runnable in this build."
    )
}

private func plannedSymptomOption(_ title: String) -> PlannedActionDescriptor {
    PlannedActionDescriptor(
        title: title,
        message: "\(title) is a planned symptom option. It does not create an Issue Case in this build."
    )
}
