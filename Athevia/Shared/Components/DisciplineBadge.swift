import SwiftUI

extension Discipline {
    /// Vivid hue for sport identity across glyphs, bars and training surfaces.
    var tint: Color {
        switch self {
        case .running: Color(red: 1.00, green: 0.42, blue: 0.16)
        case .swimming: Color(red: 0.13, green: 0.55, blue: 1.00)
        case .cycling: Color(red: 0.16, green: 0.78, blue: 0.42)
        case .multisport: Color(red: 0.62, green: 0.42, blue: 0.95)
        case .recovery: Color(red: 0.20, green: 0.78, blue: 0.85)
        case .rest: Color(red: 0.55, green: 0.56, blue: 0.62)
        }
    }

    /// Filled surface for a hero card. Two stops of the same hue give it depth
    /// without becoming a decorative gradient for its own sake.
    var gradient: LinearGradient {
        LinearGradient(
            colors: gradientStops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The deeper stop, used where a solid colour is needed. Dark enough that
    /// white text holds up, and fixed so it never inverts in dark mode.
    var surface: Color { gradientStops.last ?? tint }

    private var gradientStops: [Color] {
        switch self {
        case .running:
            [Color(red: 1.00, green: 0.48, blue: 0.22), Color(red: 0.85, green: 0.22, blue: 0.06)]
        case .swimming:
            [Color(red: 0.20, green: 0.62, blue: 1.00), Color(red: 0.04, green: 0.30, blue: 0.76)]
        case .cycling:
            [Color(red: 0.22, green: 0.80, blue: 0.45), Color(red: 0.04, green: 0.50, blue: 0.28)]
        case .multisport:
            [Color(red: 0.68, green: 0.49, blue: 1.00), Color(red: 0.39, green: 0.20, blue: 0.72)]
        case .recovery:
            [Color(red: 0.25, green: 0.82, blue: 0.88), Color(red: 0.02, green: 0.46, blue: 0.55)]
        case .rest:
            [Color(red: 0.45, green: 0.47, blue: 0.55), Color(red: 0.24, green: 0.26, blue: 0.32)]
        }
    }
}

/// Rounded sport-coloured glyph used consistently across Today, Plan and Detail.
struct DisciplineBadge: View {
    let discipline: Discipline
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: discipline.symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(discipline.tint)
            .frame(width: size, height: size)
            .background(discipline.tint.opacity(0.18), in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(Discipline.allCases, id: \.self) { discipline in
            DisciplineBadge(discipline: discipline)
        }
    }
    .padding()
}
