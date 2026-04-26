import SwiftUI

// Shared button styles keep custom ArgyllUX controls visually compact while making
// their full visible surface participate in SwiftUI hit testing.

struct ShellNavigationButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ShellNavigationButton(configuration: configuration, isSelected: isSelected)
    }
}

struct SurfaceRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minHeight: CGFloat
    let fixedWidth: CGFloat?
    let fillsAvailableWidth: Bool

    init(
        isSelected: Bool = false,
        cornerRadius: CGFloat = 10,
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 10,
        minHeight: CGFloat = 44,
        fixedWidth: CGFloat? = nil,
        fillsAvailableWidth: Bool = true
    ) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.minHeight = minHeight
        self.fixedWidth = fixedWidth
        self.fillsAvailableWidth = fillsAvailableWidth
    }

    func makeBody(configuration: Configuration) -> some View {
        SurfaceRowButton(
            configuration: configuration,
            isSelected: isSelected,
            cornerRadius: cornerRadius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            minHeight: minHeight,
            fixedWidth: fixedWidth,
            fillsAvailableWidth: fillsAvailableWidth
        )
    }
}

enum IconActionButtonTone {
    case normal
    case destructive
}

struct IconActionButtonStyle: ButtonStyle {
    let size: CGFloat
    let cornerRadius: CGFloat
    let tone: IconActionButtonTone

    init(size: CGFloat = 30, cornerRadius: CGFloat = 7, tone: IconActionButtonTone = .normal) {
        self.size = size
        self.cornerRadius = cornerRadius
        self.tone = tone
    }

    func makeBody(configuration: Configuration) -> some View {
        IconActionButton(configuration: configuration, size: size, cornerRadius: cornerRadius, tone: tone)
    }
}

struct FooterLinkButtonStyle: ButtonStyle {
    let foregroundColor: Color

    init(foregroundColor: Color = .accentColor) {
        self.foregroundColor = foregroundColor
    }

    func makeBody(configuration: Configuration) -> some View {
        FooterLinkButton(configuration: configuration, foregroundColor: foregroundColor)
    }
}

private struct ShellNavigationButton: View {
    let configuration: ButtonStyle.Configuration
    let isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 36, alignment: .center)
            .contentShape(.interaction, shape)
            .background(backgroundColor, in: shape)
            .overlay {
                if isHovered && !isSelected && isEnabled {
                    shape.stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.accentColor.opacity(isSelected ? 0.24 : 0.14)
        }

        if isSelected {
            return Color.accentColor.opacity(0.14)
        }

        if isHovered && isEnabled {
            return Color.secondary.opacity(0.10)
        }

        return Color.clear
    }
}

private struct SurfaceRowButton: View {
    let configuration: ButtonStyle.Configuration
    let isSelected: Bool
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minHeight: CGFloat
    let fixedWidth: CGFloat?
    let fillsAvailableWidth: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        sizedContent
            .contentShape(.interaction, shape)
            .background(backgroundColor, in: shape)
            .overlay {
                if isHovered && isEnabled {
                    shape.stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var sizedContent: some View {
        let content = configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(
                maxWidth: fillsAvailableWidth ? .infinity : nil,
                minHeight: minHeight,
                alignment: .leading
            )

        if let fixedWidth {
            content.frame(width: fixedWidth, alignment: .leading)
        } else {
            content
        }
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.accentColor.opacity(isSelected ? 0.24 : 0.12)
        }

        if isSelected {
            return Color.accentColor.opacity(0.14)
        }

        if isHovered && isEnabled {
            return Color.secondary.opacity(0.12)
        }

        return Color.secondary.opacity(0.08)
    }
}

private struct IconActionButton: View {
    let configuration: ButtonStyle.Configuration
    let size: CGFloat
    let cornerRadius: CGFloat
    let tone: IconActionButtonTone

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        configuration.label
            .foregroundStyle(foregroundColor)
            .frame(width: size, height: size)
            .contentShape(.interaction, shape)
            .background(backgroundColor, in: shape)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
    }

    private var foregroundColor: Color {
        switch tone {
        case .normal:
            return .secondary
        case .destructive:
            return .red
        }
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return foregroundColor.opacity(0.16)
        }

        if isHovered && isEnabled {
            return foregroundColor.opacity(0.10)
        }

        return Color.clear
    }
}

private struct FooterLinkButton: View {
    let configuration: ButtonStyle.Configuration
    let foregroundColor: Color

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minHeight: 28, alignment: .center)
            .contentShape(.interaction, shape)
            .background(backgroundColor, in: shape)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return foregroundColor.opacity(0.16)
        }

        if isHovered && isEnabled {
            return foregroundColor.opacity(0.10)
        }

        return Color.clear
    }
}
