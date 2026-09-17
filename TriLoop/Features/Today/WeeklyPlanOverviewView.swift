import SwiftUI

/// Compact whole-week context for Home. It answers how the week is shaped and
/// how far through it the athlete is without turning Home into Progress.
struct WeeklyPlanOverviewView: View {
    let plan: WeeklyPlan

    private var sessions: [PlannedWorkout] { plan.trainingSessions }

    private var completedCount: Int {
        sessions.filter(\.isCompleted).count
    }

    private var plannedSeconds: TimeInterval {
        sessions.compactMap(\.estimatedDurationSeconds).reduce(0, +)
    }

    private var activeSports: [Sport] {
        Sport.allCases.filter { sport in
            sessions.contains { $0.discipline.sport == sport }
        }
    }

    private var focus: String? {
        if let reason = plan.generationReasonCode {
            return reason.displayName
        }
        let reason = plan.generationReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? nil : reason
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Week \(plan.weekNumber)")
                            .font(.headline)
                        Text(TrainingFormatter.weekRange(start: plan.startDate, end: plan.endDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(TrainingFormatter.totalDuration(seconds: plannedSeconds)) planned")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(completedCount) of \(sessions.count) completed")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: progress)
                        .tint(.accentColor)
                }

                if !activeSports.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(activeSports, id: \.rawValue) { sport in
                            sportSummary(sport)
                        }
                    }
                }

                if let focus {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Focus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(focus)
                            .font(.caption)
                            .lineLimit(2)
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
                .foregroundStyle(sport.discipline.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(sport.discipline.displayName)
                    .font(.caption.weight(.medium))
                Text("\(sportSessions.count) · \(TrainingFormatter.totalDuration(seconds: duration))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview {
    if let plan = try? PreviewData.container.mainContext.fetch(FetchDescriptor<WeeklyPlan>()).first {
        WeeklyPlanOverviewView(plan: plan)
            .padding()
    }
}
#endif
