import SwiftUI

extension Discipline {
    var tint: Color {
        switch self {
        case .running: .orange
        case .swimming: .blue
        case .cycling: .green
        case .recovery: .teal
        case .rest: .secondary
        }
    }
}

/// Rounded, tinted sport glyph used consistently across Today, Plan and Detail.
struct DisciplineBadge: View {
    let discipline: Discipline
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: discipline.symbolName)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(discipline.tint)
            .frame(width: size, height: size)
            .background(discipline.tint.opacity(0.12), in: .rect(cornerRadius: size * 0.28))
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
