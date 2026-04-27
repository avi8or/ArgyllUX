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
                                        Text(workflowStageDisplayTitle(item.stage))
                                            .font(AppTypography.activeWorkStage)
                                            .foregroundStyle(.secondary)
                                        Text("Next: \(workflowNextActionDisplayTitle(stage: item.stage, rawTitle: item.nextAction))")
                                            .font(AppTypography.activeWorkSupporting)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .buttonStyle(SurfaceRowButtonStyle(fixedWidth: 260, fillsAvailableWidth: false))

                                Button(role: .destructive) {
                                    onDelete(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(AppTypography.shellUtility.weight(.semibold))
                                }
                                .buttonStyle(IconActionButtonStyle(size: 30, tone: .destructive))
                                .accessibilityLabel(ActiveWorkCopy.deleteAccessibilityLabel(for: item.title, jobId: item.id))
                                .accessibilityHint(ActiveWorkCopy.deleteHint)
                                .help(ActiveWorkCopy.deleteActionTitle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
