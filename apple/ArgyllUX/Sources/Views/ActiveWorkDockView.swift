import SwiftUI

struct ActiveWorkDockView: View {
    let items: [ActiveWorkItem]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Active work")
                .font(.headline)

            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    Text("Next: \(item.nextAction)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
