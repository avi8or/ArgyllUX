import SwiftUI

struct ActiveWorkDockView: View {
    let items: [ActiveWorkItem]
    let onSelect: (ActiveWorkItem) -> Void
    let onDelete: (ActiveWorkItem) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Active work")
                .font(.headline)

            if items.isEmpty {
                Text(ActiveWorkCopy.emptyStateMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.id) { item in
                    HStack(spacing: 8) {
                        Button {
                            onSelect(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(stageTitle(item.stage))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("Next: \(item.nextAction)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            onDelete(item)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption.weight(.semibold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ActiveWorkCopy.deleteAccessibilityLabel(for: item.title))
                        .accessibilityHint(ActiveWorkCopy.deleteHint)
                        .help(ActiveWorkCopy.deleteActionTitle)
                    }
                    .padding(.trailing, 4)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func stageTitle(_ stage: WorkflowStage) -> String {
        switch stage {
        case .context:
            "Context"
        case .target:
            "Target"
        case .print:
            "Print"
        case .drying:
            "Drying"
        case .measure:
            "Measure"
        case .build:
            "Build"
        case .review:
            "Review"
        case .publish:
            "Publish"
        case .completed:
            "Completed"
        case .blocked:
            "Blocked"
        case .failed:
            "Failed"
        }
    }
}
