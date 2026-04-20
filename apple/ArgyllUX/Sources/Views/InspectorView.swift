import SwiftUI

struct InspectorView: View {
    let route: AppRoute
    let appHealth: AppHealth?
    let toolchainStatus: ToolchainStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorSection(title: "Recommended", body: route.inspectorNote)

                inspectorSection(
                    title: "Advanced",
                    body: "The foundation pass keeps this rail in place so route-specific details can land without reshaping the shell."
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Technical")
                        .font(.headline)

                    detailRow(title: "Toolchain", value: technicalToolchainLabel)
                    detailRow(title: "Last validation", value: toolchainStatus?.lastValidationTime ?? "Waiting for validation")
                    detailRow(title: "Readiness", value: appHealth?.readiness.capitalized ?? "Blocked")
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var technicalToolchainLabel: String {
        switch toolchainStatus?.state {
        case .ready:
            "Ready"
        case .partial:
            "Partial"
        case .notFound, .none:
            "Not Found"
        }
    }

    private func inspectorSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }
}
