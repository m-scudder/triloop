import SwiftUI

/// Time in each heart-rate zone (§29).
///
/// A bar per zone rather than a pie: the question is "how long", and length
/// compares far better than angle.
struct HeartRateZoneView: View {
    let breakdown: HeartRateZoneBreakdown

    private static let tints: [Color] = [
        Color(red: 0.16, green: 0.62, blue: 0.98),
        Color(red: 0.20, green: 0.80, blue: 0.55),
        Color(red: 0.95, green: 0.77, blue: 0.20),
        Color(red: 0.98, green: 0.55, blue: 0.15),
        Color(red: 0.95, green: 0.26, blue: 0.21)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Heart-rate zones")

            VStack(spacing: 8) {
                ForEach(breakdown.zones) { zone in
                    row(for: zone)
                }
            }

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(for zone: HeartRateZone) -> some View {
        let share = breakdown.share(of: zone)

        return HStack(spacing: 10) {
            Text("Z\(zone.number)")
                .font(.subheadline.weight(.medium))
                .frame(width: 26, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(Self.tints[zone.number - 1])
                        .frame(width: max(proxy.size.width * share, share > 0 ? 3 : 0))
                }
            }
            .frame(height: 10)

            Text(TrainingFormatter.totalDuration(seconds: zone.duration))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)

            Text("\(Int((share * 100).rounded()))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    /// States the ceiling the zones were measured against, so a reading that
    /// looks wrong can be attributed rather than guessed at.
    private var caption: String {
        let top = breakdown.zones.last?.lowerBoundBPM ?? 0
        let maximum = Int((top / 0.9).rounded())

        return switch breakdown.source {
        case .ageBasedMaximum: "Measured against an age-estimated maximum of about \(maximum) bpm."
        case .observedMaximum: "Measured against \(maximum) bpm, the hardest effort in your history."
        }
    }
}
