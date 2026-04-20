import SwiftUI

struct StatusBadgeView: View {
    let title: String
    let tone: Tone

    enum Tone {
        case ready
        case attention
        case blocked

        var foregroundColor: Color {
            switch self {
            case .ready:
                Color.green
            case .attention:
                Color.orange
            case .blocked:
                Color.red
            }
        }

        var backgroundColor: Color {
            foregroundColor.opacity(0.12)
        }
    }

    var body: some View {
        Text(title)
            .font(AppTypography.statusBadge)
            .foregroundStyle(tone.foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tone.backgroundColor, in: Capsule())
    }
}
