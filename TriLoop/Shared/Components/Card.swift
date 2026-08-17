import SwiftUI

extension Color {
    /// Fixed dark surface for the focus card and primary actions.
    ///
    /// Deliberately not `.primary`, which is an adaptive *foreground* colour and
    /// inverts to white in dark mode, hiding white text on top of it.
    static let focusSurface = Color(red: 0.10, green: 0.11, blue: 0.12)

    /// Text and glyphs drawn on `focusSurface`, in both appearances.
    static let onFocusSurface = Color.white
}

/// Small uppercase label above a group, as used throughout the wireframes.
struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Bordered container used for grouped content outside of `List`.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            )
    }
}

/// A single headline figure with its caption, e.g. "12 / Workouts".
struct StatTile: View {
    let value: String
    let label: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
                Capsule().fill(.fill.tertiary)
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
                    Capsule().fill(.fill.tertiary)
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
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target effort \(TrainingFormatter.rpe(range)) out of \(RPEScale.maximum)")
    }
}
