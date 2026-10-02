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
    @State private var showingFourWeekInfo = false

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
        .sheet(isPresented: $showingFourWeekInfo) {
            fourWeekInfoSheet
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
                    currentTraining(current)
                }

                if !snapshot.milestones.isEmpty {
                    JourneyProgressView(snapshot: snapshot)
                }
            } else {
                fourWeekSummary

                if let current, current.hasData {
                    currentTraining(current)
                }
            }
        }
    }

    private func compactEventJourney(
        setup: AthleteSetup,
        snapshot: JourneyProgressSnapshot
    ) -> some View {
        let eventName = setup.objective.event?.displayName
            ?? setup.objective.displayName

        return VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Journey")

            NavigationLink {
                FullTrainingJourneyView(
                    setup: setup,
                    plans: plans
                )
            } label: {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "flag.checkered")
                            .font(.headline)

                        Text(eventName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                AtheviaAdaptiveStyle(
                                    .tertiary,
                                    gaming: .secondaryText
                                )
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(eventName), open race journey"
            )
        }
    }

    /// One glance at recent consistency before the athlete reads any deeper
    /// training metrics.
    private var fourWeekSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionEyebrow(text: "Last 4 weeks")

                Spacer()

                Button {
                    showingFourWeekInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "About your last four weeks"
                )
            }

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

    private var fourWeekInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if let current, current.hasData {
                    let summary = interpretation(for: current)

                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            summary.title,
                            systemImage: summary.symbol
                        )
                        .font(.headline)

                        Text(summary.detail)
                            .font(.body)
                            .foregroundStyle(
                                AtheviaAdaptiveStyle(
                                    .secondary,
                                    gaming: .secondaryText
                                )
                            )
                    }
                } else {
                    Text(
                        "Complete a few workouts to build a clearer progress picture."
                    )
                    .font(.body)
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    infoRow(
                        "Training",
                        detail:
                            "Total completed training time from the last four plan weeks."
                    )
                    infoRow(
                        "Workouts",
                        detail:
                            "Completed planned workouts from those weeks."
                    )
                    infoRow(
                        "Plan completed",
                        detail:
                            "The share of planned workouts due so far that you completed."
                    )
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Last 4 weeks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingFourWeekInfo = false
                    }
                }
            }
        }
        .atheviaScreen()
        .presentationDetents([.medium])
    }

    private func infoRow(
        _ title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(
                    AtheviaAdaptiveStyle(
                        .secondary,
                        gaming: .secondaryText
                    )
                )
        }
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
