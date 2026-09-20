import SwiftUI

extension AssessmentStatus {
    var tint: Color {
        switch self {
        case .progress: .green
        case .maintain: .orange
        case .reduce: .red
        case .recoveryRequired: .red
        }
    }

    /// Short banner headline for a whole week, phrased as a coach would rather
    /// than as a score (§44).
    var weekHeadline: String {
        switch self {
        case .progress: "Great week"
        case .maintain: "Solid week"
        case .reduce: "Ease back this week"
        case .recoveryRequired: "Recovery comes first"
        }
    }
}

/// Coloured capsule carrying a sport's verdict.
struct StatusPill: View {
    let status: AssessmentStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.4)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.tint.opacity(0.16), in: .capsule)
            .foregroundStyle(status.tint)
            .accessibilityLabel("Status \(status.displayName)")
    }
}
