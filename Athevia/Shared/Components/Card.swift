import SwiftUI
import UIKit

extension Color {
    /// Fixed dark surface for the focus card and primary actions.
    ///
    /// Deliberately not `.primary`, which is an adaptive *foreground* colour and
    /// inverts to white in dark mode, hiding white text on top of it.
    static let focusSurface = Color(red: 0.10, green: 0.11, blue: 0.12)

    /// Text and glyphs drawn on `focusSurface`, in both appearances.
    static let onFocusSurface = Color.white

    /// Filled button surface. Inverts with the appearance, because a fixed dark
    /// fill disappears against a dark background.
    static let actionSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.94, alpha: 1)
            : UIColor(red: 0.10, green: 0.11, blue: 0.12, alpha: 1)
    })

    static let onActionSurface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.07, alpha: 1)
            : .white
    })
}

/// Filled, full-width button for the one action a screen most wants.
struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.atheviaTheme) private var theme

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.color(.accent, classic: Color.actionSurface), in: .rect(cornerRadius: 12))
            .foregroundStyle(theme.color(.onAccent, classic: Color.onActionSurface))
            .shadow(color: theme.isGaming ? GamingPalette.color(.onAccent).opacity(0.65) : .clear, radius: 0, y: configuration.isPressed ? 0 : 3)
            .opacity(opacity(pressed: configuration.isPressed))
    }

    private func opacity(pressed: Bool) -> Double {
        if !isEnabled { return 0.4 }
        return pressed ? 0.85 : 1
    }
}

/// Companion to `PrimaryActionButtonStyle`, for actions that sit beside it.
///
/// Carries a border as well as a fill: the system fill styles are nearly
/// invisible against a dark background on their own.
struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface), in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AtheviaAdaptiveStyle(.separator, gaming: .border), lineWidth: 0.5)
            )
            .opacity(opacity(pressed: configuration.isPressed))
    }

    private func opacity(pressed: Bool) -> Double {
        if !isEnabled { return 0.5 }
        return pressed ? 0.85 : 1
    }
}

/// Small uppercase label above a group, as used throughout the wireframes.
struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .highlight))
    }
}

/// Bordered container used for grouped content outside of `List`.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var gamingRole: GamingPalette.Role = .surface
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AtheviaAdaptiveStyle(.background.secondary, gaming: gamingRole))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AtheviaAdaptiveStyle(.separator.opacity(0.6), gaming: .border), lineWidth: 0.5)
            )
    }
}

/// A native disclosure row inside the same quiet surface used by `Card`.
///
/// Secondary information stays one tap away without competing with the
/// screen's primary task. The summary remains visible when the content is
/// collapsed, which is important on workout screens where the athlete should
/// know what is available without seeing every chart and control at once.
struct DisclosureCard<Content: View>: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    @ViewBuilder var content: Content

    @State private var isExpanded: Bool

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String,
        initiallyExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 16)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                            .lineLimit(2)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    .frame(width: 24)
            }
        }
        .tint(.secondary)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AtheviaAdaptiveStyle(.background.secondary, gaming: .surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AtheviaAdaptiveStyle(.separator.opacity(0.45), gaming: .border), lineWidth: 0.5)
        )
    }
}

/// A single headline figure with its caption, e.g. "12 / Workouts".
struct StatTile: View {
    let value: String
    let label: String
    var alignment: HorizontalAlignment = .leading
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Horizontal proportion bar used for per-sport volume.
struct ProportionBar: View {
    let fraction: Double
    var tint: Color = .primary

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface))
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), 2))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Target-effort scale with its easy/maximum anchors.
struct EffortBar: View {
    let range: RPERange

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let lower = Double(range.lower - RPEScale.minimum) / Double(RPEScale.maximum - RPEScale.minimum)
                let upper = Double(range.upper - RPEScale.minimum) / Double(RPEScale.maximum - RPEScale.minimum)

                ZStack(alignment: .leading) {
                    Capsule().fill(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface))
                    Capsule()
                        .fill(.primary)
                        .frame(width: max((upper - lower) * width, 6))
                        .offset(x: lower * width)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(RPEScale.minimum) Easy")
                Spacer()
                Text("\(RPEScale.maximum) Max")
            }
            .font(.caption2)
            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target effort \(TrainingFormatter.rpe(range)) out of \(RPEScale.maximum)")
    }
}


struct AtheviaToggleStyle: ToggleStyle {
    @Environment(\.atheviaTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? theme.color(.accent, classic: .green) : theme.color(.raisedSurface, classic: Color(uiColor: .tertiarySystemFill)))
                        .frame(width: 50, height: 30)
                    Circle()
                        .fill(theme.color(.onAccent, classic: .white))
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                        .padding(3)
                }
                .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct AtheviaProgressOverlay: ViewModifier {
    let message: String?

    func body(content: Content) -> some View {
        content
            .disabled(message != nil)
            .overlay {
                if let message {
                    ZStack {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.large)
                            Text(message)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 26)
                        .padding(.vertical, 22)
                        .background(AtheviaAdaptiveStyle(.regularMaterial, gaming: .surface), in: .rect(cornerRadius: 16))
                        .shadow(radius: 12, y: 4)
                        .padding(32)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: message)
    }
}

extension View {
    func atheviaProgress(_ message: String?) -> some View {
        modifier(AtheviaProgressOverlay(message: message))
    }
}


/// Compact selectable control for low-friction choice groups.
///
/// Use this instead of pushing a short set of mutually exclusive options into
/// another screen or sheet. The selected fill is explicit so it remains
/// readable in both light and dark appearances.
struct AtheviaChoiceChip: View {
    @Environment(\.atheviaTheme) private var theme
    let title: String
    let isSelected: Bool
    var tint: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(isSelected ? theme.color(.onAccent, classic: .white) : theme.color(.text, classic: .primary))
                .frame(maxWidth: .infinity, minHeight: 42)
                .padding(.horizontal, 8)
                .background(
                    isSelected ? theme.color(.accent, classic: tint) : theme.color(.raisedSurface, classic: Color(uiColor: .tertiarySystemFill)),
                    in: .rect(cornerRadius: 11)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            isSelected ? theme.color(.accent, classic: tint) : theme.color(.border, classic: Color.secondary.opacity(0.16)),
                            lineWidth: 0.5
                        )
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
