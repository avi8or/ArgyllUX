import SwiftUI

struct AppShellView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            Divider()

            HStack(spacing: 0) {
                currentRouteView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                InspectorView(
                    route: model.selectedRoute,
                    appHealth: model.appHealth,
                    toolchainStatus: model.toolchainStatus
                )
                .frame(width: 300)
            }

            Divider()

            ActiveWorkDockView(items: model.activeWorkItems)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await model.bootstrapIfNeeded()
        }
    }

    private var topStrip: some View {
        HStack(spacing: 16) {
            Text("ArgyllUX")
                .font(.title3.weight(.semibold))

            ForEach(AppRoute.allCases) { route in
                Button {
                    model.selectedRoute = route
                } label: {
                    Label(route.title, systemImage: route.symbolName)
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(model.selectedRoute == route ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            model.selectedRoute == route
                                ? Color.accentColor.opacity(0.14)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            utilityPill(title: "Search / Jump")
            utilityPill(title: "Instrument: Not Connected")
            utilityPill(title: "Jobs 0")
            utilityPill(title: "Alerts 0")
            utilityPill(title: model.argyllStatusLabel)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var currentRouteView: some View {
        switch model.selectedRoute {
        case .home:
            HomeView(model: model)
        case .settings:
            SettingsView(model: model)
        case .printerProfiles, .troubleshoot, .inspect, .blackAndWhiteTuning:
            PlaceholderRouteView(route: model.selectedRoute)
        }
    }

    private func utilityPill(title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}
