import Charts
import SwiftData
import SwiftUI

/// Progress answers three questions without duplicating Plan:
/// Am I progressing? What has my training looked like? How is recovery trending?
struct ProgressOverviewView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    private enum Segment: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case training = "Training"
        case recovery = "Recovery"

        var id: Self { self }
    }

    @State private var segment: Segment = .overview

    private var current: CurrentTraining? {
        CurrentTraining(plans: plans)
    }

    private var recentPlans: [WeeklyPlan] {
        Array(plans.sorted { $0.startDate < $1.startDate }.suffix(4))
    }

    private var recentSessions: [PlannedWorkout] {
        recentPlans.flatMap(\.prescribedTrainingSessions)
    }

    private var completedRecentSessions: [PlannedWorkout] {
        recentSessions.filter(\.isCompleted)
    }

    private var recentTrainingSeconds: TimeInterval {
        completedRecentSessions.reduce(0) { total, session in
            total + (session.importedSummary?.duration ?? session.estimatedDurationSeconds ?? 0)
        }
    }

    /// Adherence only counts sessions whose scheduled day has arrived. Future
    /// sessions in the current week should not make today's progress look worse.
    private var recentAdherence: Double? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let due = recentSessions.filter { calendar.startOfDay(for: $0.date) <= today }
        guard !due.isEmpty else { return nil }
        return Double(due.filter(\.isCompleted).count) / Double(due.count)
    }

    private var weeklyTrend: [ProgressWeekSummary] {
        recentPlans.map { plan in
            let seconds = plan.completedPrescribedTrainingSessions.reduce(0) { total, session in
                total + (session.importedSummary?.duration ?? session.estimatedDurationSeconds ?? 0)
            }
            return ProgressWeekSummary(
                id: plan.id,
                weekNumber: plan.weekNumber,
                startDate: plan.startDate,
                seconds: seconds
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Progress view", selection: $segment) {
                    ForEach(Segment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch segment {
                        case .overview:
                            overviewContent
                        case .training:
                            TrainingIntelligenceView()
                        case .recovery:
                            ProgressRecoveryView()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        if plans.isEmpty {
            ContentUnavailableView(
                "No progress yet",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Your progress will appear here as you complete training.")
            )
            .padding(.top, 60)
        } else {
            fourWeekSummary

            if let current, current.hasData {
                currentTraining(current)
            }

            if weeklyTrend.contains(where: { $0.seconds > 0 }) {
                trainingTrend
            }
        }
    }

    /// One glance at recent consistency before the athlete reads any deeper
    /// training metrics.
    private var fourWeekSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Last 4 weeks")

            Card {
                HStack(alignment: .top, spacing: 8) {
                    summaryFigure(
                        TrainingFormatter.totalDuration(seconds: recentTrainingSeconds),
                        caption: "Training"
                    )
                    summaryFigure(
                        "\(completedRecentSessions.count)",
                        caption: completedRecentSessions.count == 1 ? "Workout" : "Workouts"
                    )
                    summaryFigure(
                        recentAdherence.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                        caption: "Adherence"
                    )
                }
            }
        }
    }

    /// Current capability/prescription plus the most recent training direction.
    /// It says where each sport is heading without asking the athlete to open a
    /// week review or inspect individual sessions.
    private func currentTraining(_ current: CurrentTraining) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Your progress")

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(current.states) { state in
                        HStack(spacing: 14) {
                            Image(systemName: state.sport.discipline.symbolName)
                                .font(.headline)
                                .foregroundStyle(state.sport.discipline.tint)
                                .frame(width: 38, height: 38)
                                .background(state.sport.discipline.tint.opacity(0.12), in: .circle)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(state.sport.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(state.prescription)
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            if let status = state.status {
                                Label(status.directionLabel, systemImage: status.directionSymbol)
                                    .labelStyle(.titleAndIcon)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(status.tint)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if state.id != current.states.last?.id {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
            }
        }
    }

    /// Keep Overview to one visual trend. Detailed load/intensity/balance live
    /// in Training rather than competing for attention here.
    private var trainingTrend: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Training trend")

            Card {
                Chart(weeklyTrend) { week in
                    BarMark(
                        x: .value("Week", week.startDate, unit: .weekOfYear),
                        y: .value("Training minutes", week.seconds / 60)
                    )
                    .cornerRadius(3)
                }
                .frame(height: 130)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(4, weeklyTrend.count))) {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }

                Text("Completed training time by week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summaryFigure(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgressWeekSummary: Identifiable {
    let id: UUID
    let weekNumber: Int
    let startDate: Date
    let seconds: TimeInterval
}

#if DEBUG
#Preview {
    ProgressOverviewView()
        .modelContainer(PreviewData.container)
}
#endif
