import SwiftUI

/// Shared operational label/value pair for workflow evidence and trust metadata.
struct OperationalDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.detailLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppTypography.detailValue)
                .textSelection(.enabled)
        }
    }
}
