import SwiftUI

struct PlaceholderRouteView: View {
    let route: AppRoute

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(route.title)
                    .font(.largeTitle.weight(.semibold))

                Text(route.placeholderSummary)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(route.placeholderSections, id: \.self) { section in
                        HStack {
                            Text(section)
                            Spacer()
                            Text("Placeholder")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
