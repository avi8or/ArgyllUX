import SwiftUI

/// Presents unavailable product actions without making them look runnable.
/// Planned actions are informational status surfaces, not disabled buttons.
struct PlannedActionSurface: View {
    let descriptor: PlannedActionDescriptor
    var minimumHeight: CGFloat = 44

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(descriptor.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(descriptor.status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(descriptor.accessibilityLabel)
        .help(descriptor.help)
    }
}

struct PlannedChipSurface: View {
    let descriptor: PlannedActionDescriptor

    var body: some View {
        Text("\(descriptor.title) - \(descriptor.status)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
            .accessibilityLabel(descriptor.accessibilityLabel)
            .help(descriptor.help)
    }
}
