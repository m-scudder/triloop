import SwiftUI

/// Compact whole-week context for Home. It answers how the week is shaped and
/// how far through it the athlete is without turning Home into Progress.
struct WeeklyPlanOverviewView: View {
    @Environment(\.atheviaTheme) private var theme

    let plan: WeeklyPlan

    /// This card describes the plan, not every activity recorded this week.
    /// Extra Health workouts remain in history/analytics but must not inflate
    /// the planned-session denominator or sport mix shown on Home.
    private var sessions: [PlannedWorkout] { plan.prescribedWorkouts }

    private var completedCount: Int {
        sessions.filter(\.isCompleted).count
    }

    private var recoveryCount: Int {
        sessions.count { $0.discipline == .recovery }
    }

    private var activeSports: [Sport] {
        Sport.allCases.filter { sport in
            sessions.contains { $0.discipline.sport == sport }
        }
    }

    var body: some View {
        Card(padding: 12, gamingRole: .hero) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Week \(plan.weekNumber)")
                        .font(.headline)

                    Spacer()

                    Text(TrainingFormatter.weekRange(start: plan.startDate, end: plan.endDate))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }

                HStack(spacing: 10) {
                    Text("\(completedCount)/\(sessions.count) completed")
                        .font(.caption.weight(.medium))

                    ProgressView(value: progress)
                        .tint(.accentColor)

                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }

                if !activeSports.isEmpty || recoveryCount > 0 {
                    HStack(spacing: 12) {
                        ForEach(activeSports, id: \.rawValue) { sport in
                            sportSummary(sport)
                        }

                        if recoveryCount > 0 {
                            Label("\(recoveryCount)", systemImage: Discipline.recovery.symbolName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            }
        }
    }

    private var progress: Double {
        guard !sessions.isEmpty else { return 0 }
        return Double(completedCount) / Double(sessions.count)
    }

    private func sportSummary(_ sport: Sport) -> some View {
        let sportSessions = sessions.filter { $0.discipline.sport == sport }
        let duration = sportSessions.compactMap(\.estimatedDurationSeconds).reduce(0, +)

        return HStack(spacing: 6) {
            Image(systemName: sport.discipline.symbolName)
                .foregroundStyle(sport.discipline.themedTint(theme))
            VStack(alignment: .leading, spacing: 1) {
                Text(sport.discipline.displayName)
                    .font(.caption.weight(.medium))
                Text("\(sportSessions.count) · \(TrainingFormatter.totalDuration(seconds: duration))")
                    .font(.caption2)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
