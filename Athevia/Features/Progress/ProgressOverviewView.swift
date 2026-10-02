import SwiftData
import SwiftUI

/// Progress answers three questions without duplicating Plan:
/// Am I progressing? What has my training looked like? How is recovery trending?
struct ProgressOverviewView: View {
    @Environment(\.atheviaTheme) private var theme

    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @Query private var profiles: [AthleteProfile]

    private enum Segment: String, CaseIterable, Identifiable {
        case overview = "Overview"
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Progress")
                    .font(.headline)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

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
                        case .recovery:
                            ProgressRecoveryView()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .atheviaScreen()
            .toolbar(.hidden, for: .navigationBar)
            .analyticsScreen(.progress)
        }
        .atheviaScreen()
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
            if let setup = profiles.first?.setup {
                let snapshot = JourneyProgressBuilder().build(
                    setup: setup,
                    plans: plans
                )

                if setup.objective.kind == .event {
                    compactEventJourney(
                        setup: setup,
                        snapshot: snapshot
                    )

                    if let profile = profiles.first {
                        EventOutcomeResolutionCard(profile: profile)
                    }

                    if snapshot.journey.phase == .raceWeek,
                       let event = setup.objective.event,
                       !snapshot.journey.eventResolutionRequired {
                        RaceWeekPreparationView(event: event)
                    }

                    if snapshot.journey.requiresNextObjective,
                       let event = setup.objective.event,
                       let profile = profiles.first {
                        NextObjectivePromptView(
                            event: event,
                            profile: profile
                        )
                    }
                }

                fourWeekSummary

                if let current, current.hasData {
                    progressInterpretation(current)
                    currentTraining(current)
                }

                if !snapshot.milestones.isEmpty {
                    JourneyProgressView(snapshot: snapshot)
                }
            } else {
                fourWeekSummary

                if let current, current.hasData {
                    progressInterpretation(current)
                    currentTraining(current)
                }
            }
        }
    }

    private func compactEventJourney(
        setup: AthleteSetup,
        snapshot: JourneyProgressSnapshot
    ) -> some View {
        let journey = snapshot.journey
        let eventName = setup.objective.event?.displayName
            ?? setup.objective.displayName

        var parts = [
            eventName,
            journey.phase.displayName
        ]

        if let weeks = journey.weeksRemaining {
            parts.append(
                weeks == 1
                    ? "1 week"
                    : "\(weeks) weeks"
            )
        }

        return VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Journey")

            Card {
                Label(
                    parts.joined(separator: " · "),
                    systemImage: "flag.checkered"
                )
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
                        caption: "Plan completed"
                    )
                }
            }
        }
    }

    private func progressInterpretation(_ current: CurrentTraining) -> some View {
        let summary = interpretation(for: current)

        return VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "What this means")

            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Label(summary.title, systemImage: summary.symbol)
                        .font(.headline)

                    Text(summary.detail)
                        .font(.subheadline)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func interpretation(
        for current: CurrentTraining
    ) -> (title: String, detail: String, symbol: String) {
        let statuses = current.states.compactMap(\.status)

        if statuses.contains(.recoveryRequired) {
            return (
                "Recovery is leading the plan",
                "One or more sports needs extra recovery, so your upcoming training is lighter.",
                "pause.circle"
            )
        }

        if statuses.contains(.reduce) {
            return (
                "Athevia is easing training back",
                "Recent workouts suggest backing off a little before building again.",
                "arrow.down.right.circle"
            )
        }

        if statuses.contains(.maintain) {
            return (
                "Training is holding steady",
                "Your training is staying steady while Athevia gathers more completed workouts.",
                "arrow.right.circle"
            )
        }

        if !statuses.isEmpty && statuses.allSatisfy({ $0 == .progress }) {
            return (
                "Training is building gradually",
                "Your recent workouts support gradually increasing training.",
                "arrow.up.right.circle"
            )
        }

        return (
            "Building your progress picture",
            "Complete a few more workouts to show a clearer progress direction.",
            "chart.line.uptrend.xyaxis"
        )
    }

    /// Sport-level progress stays intentionally simple. Prescription details
    /// belong to Plan; Progress only says which direction each sport is moving.
    private func currentTraining(_ current: CurrentTraining) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Your progress")

            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(current.states) { state in
                        HStack(spacing: 14) {
                            Image(
                                systemName:
                                    state.sport.discipline.symbolName
                            )
                            .font(.headline)
                            .foregroundStyle(
                                state.sport.discipline
                                    .themedTint(theme)
                            )
                            .frame(width: 38, height: 38)
                            .background(
                                state.sport.discipline
                                    .themedTint(theme)
                                    .opacity(0.12),
                                in: .circle
                            )

                            Text(state.sport.displayName)
                                .font(.subheadline.weight(.semibold))

                            Spacer(minLength: 8)

                            if let status = state.status {
                                Label(
                                    status.directionLabel,
                                    systemImage:
                                        status.directionSymbol
                                )
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(status.tint)
                            } else {
                                Text("Building history")
                                    .font(.caption)
                                    .foregroundStyle(
                                        AtheviaAdaptiveStyle(
                                            .secondary,
                                            gaming: .secondaryText
                                        )
                                    )
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

    private func summaryFigure(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.caption)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#if DEBUG
#Preview {
    ProgressOverviewView()
        .modelContainer(PreviewData.container)
}
#endif
