import SwiftUI

struct ActiveWorkDockView: View {
    let items: [ActiveWorkItem]
    let onSelect: (ActiveWorkItem) -> Void
    let onDelete: (ActiveWorkItem) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Active work")
                .font(.headline)
                .frame(width: 110, alignment: .leading)

            if items.isEmpty {
                Text(ActiveWorkCopy.emptyStateMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items, id: \.id) { item in
                            HStack(spacing: 8) {
                                Button {
                                    onSelect(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(AppTypography.activeWorkTitle)
                                            .foregroundStyle(.primary)
                                        Text(stageTitle(item.stage))
                                            .font(AppTypography.activeWorkStage)
                                            .foregroundStyle(.secondary)
                                        Text("Next: \(item.nextAction)")
                                            .font(AppTypography.activeWorkSupporting)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(width: 260, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    onDelete(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(AppTypography.shellUtility.weight(.semibold))
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(ActiveWorkCopy.deleteAccessibilityLabel(for: item.title))
                                .accessibilityHint(ActiveWorkCopy.deleteHint)
                                .help(ActiveWorkCopy.deleteActionTitle)
                            }
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
