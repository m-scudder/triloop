import SwiftUI

/// Visual race-day roadmap. The current generated week remains authoritative;
/// later weeks are projections from the deterministic journey planner.
struct FullTrainingJourneyView: View {
    @Environment(\.atheviaTheme) private var theme

    let setup: AthleteSetup
    let plans: [WeeklyPlan]

    private var event: AthleteEventGoal? {
        setup.objective.event
    }

    private var weeks: [JourneyWeekProjection] {
        JourneyWeekProjection.make(setup: setup, plans: plans)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let event, let eventDate = event.eventDate {
                    raceHeader(event: event, eventDate: eventDate)
                    phaseStrip

                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "Road to race day")

                        ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                            JourneyWeekRow(
                                week: week,
                                setup: setup,
                                plans: plans,
                                isLast: index == weeks.count - 1
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .atheviaScreen()
        .navigationTitle("Race Plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func raceHeader(event: AthleteEventGoal, eventDate: Date) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(theme.color(.raisedSurface, classic: Color.primary.opacity(0.08)))
                            .frame(width: 44, height: 44)

                        Image(systemName: "flag.checkered")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.displayName)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)

                        Text(TrainingFormatter.shortDate(eventDate, includeYear: true))
                            .font(.subheadline)
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    }

                    Spacer(minLength: 8)

                    if let days = event.daysRemaining(), days >= 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(days)")
                                .font(.title2.weight(.bold).monospacedDigit())
                            Text(days == 1 ? "day" : "days")
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        }
                    }
                }

                if let current = weeks.first {
                    HStack(spacing: 8) {
                        phasePill(current.phase)
                        Spacer()
                        Text(current.focus)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var phaseStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(weeks) { week in
                    Capsule()
                        .fill(week.phase.tint(theme: theme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 7)
                }
            }

            HStack {
                if let first = weeks.first {
                    Text(first.phase.shortName)
                }
                Spacer()
                Text("Race")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training phases from now to race day")
    }

    private func phasePill(_ phase: TrainingPhase) -> some View {
        Label(phase.shortName, systemImage: phase.symbolName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(phase.tint(theme: theme).opacity(0.14), in: .capsule)
            .foregroundStyle(phase.tint(theme: theme))
    }
}

private struct JourneyWeekRow: View {
    @Environment(\.atheviaTheme) private var theme

    let week: JourneyWeekProjection
    let setup: AthleteSetup
    let plans: [WeeklyPlan]
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(week.phase.tint(theme: theme))
                        .frame(width: 26, height: 26)

                    Image(systemName: week.isRaceWeek ? "flag.checkered" : week.phase.symbolName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }

                if !isLast {
                    Rectangle()
                        .fill(AtheviaAdaptiveStyle(.separator.opacity(0.7), gaming: .border))
                        .frame(width: 1)
                        .frame(minHeight: 64)
                }
            }

            NavigationLink {
                JourneyWeekPlanView(
                    week: week,
                    setup: setup,
                    plans: plans
                )
            } label: {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 7) {
                                    Text(week.title)
                                        .font(.subheadline.weight(.semibold))

                                    if week.isCurrent {
                                        Text("NOW")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(week.phase.tint(theme: theme).opacity(0.14), in: .capsule)
                                            .foregroundStyle(week.phase.tint(theme: theme))
                                    }
                                }

                                Text(week.dateRange)
                                    .font(.caption)
                                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                            }

                            Spacer(minLength: 8)

                            HStack(spacing: 6) {
                                Text(week.phase.shortName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(week.phase.tint(theme: theme))

                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AtheviaAdaptiveStyle(.tertiary, gaming: .secondaryText))
                            }
                        }

                        HStack(spacing: 12) {
                            Label(week.sessionLabel, systemImage: "figure.run")
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))

                            Spacer()

                            Text(week.focus)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }

                        if !week.sports.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(week.sports, id: \.self) { sport in
                                    Image(systemName: sport.discipline.symbolName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(sport.discipline.themedTint(theme))
                                        .frame(width: 26, height: 26)
                                        .background(
                                            sport.discipline.themedTint(theme).opacity(0.10),
                                            in: .circle
                                        )
                                }

                                Spacer()
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct JourneyWeekPlanView: View {
    @State private var showingInfo = false

    let week: JourneyWeekProjection
    let setup: AthleteSetup
    let plans: [WeeklyPlan]

    private var existingPlan: WeeklyPlan? {
        plans.first {
            $0.endDate >= week.startDate && $0.startDate <= week.endDate
        }
    }

    private var displayedPlan: WeeklyPlan? {
        if let existingPlan {
            return existingPlan
        }

        let poolLength = plans
            .sorted { $0.startDate < $1.startDate }
            .last?
            .parameters
            .swimPoolLengthMeters ?? 25

        let nextWeekNumber = (plans.map(\.weekNumber).max() ?? 0) + week.weekIndex

        return try? FirstWeekBuilder().build(
            setup: setup,
            poolLengthMeters: poolLength,
            startDate: week.startDate,
            weekNumber: nextWeekNumber
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(week.phase.shortName)
                            .font(.subheadline.weight(.semibold))
                        Text(week.focus)
                            .font(.caption)
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    }

                    Spacer()

                    Button {
                        showingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About this training week")
                }

                if let plan = displayedPlan {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(plan.orderedWorkouts, id: \.id) { workout in
                                HStack(spacing: 12) {
                                    DisciplineBadge(discipline: workout.discipline, size: 38)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(TrainingFormatter.shortDate(workout.date))
                                            .font(.subheadline.weight(.medium))

                                        Text(workoutDetail(workout))
                                            .font(.caption)
                                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                            .lineLimit(2)
                                    }

                                    Spacer(minLength: 8)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)

                                if workout.id != plan.orderedWorkouts.last?.id {
                                    Divider().padding(.leading, 62)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .atheviaScreen()
        .sheet(isPresented: $showingInfo) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image(systemName: week.phase.symbolName)
                            .font(.title2)
                        Text(week.phase.shortName)
                            .font(.title3.weight(.semibold))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("What this means")
                            .font(.subheadline.weight(.semibold))
                        Text(week.phase.beginnerExplanation)
                            .font(.body)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("This week's focus")
                            .font(.subheadline.weight(.semibold))
                        Text(week.focus.beginnerFocusExplanation)
                            .font(.body)
                    }

                    if let plan = displayedPlan, !plan.generationReason.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Why this week")
                                .font(.subheadline.weight(.semibold))
                            Text(plan.generationReason)
                                .font(.body)
                        }
                    }

                    if week.isProjected {
                        Text("This week can change as your training progresses.")
                            .font(.footnote)
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    }

                    Spacer()
                }
                .padding(20)
                .navigationTitle("Training Guide")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showingInfo = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .navigationTitle(week.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func workoutDetail(_ workout: PlannedWorkout) -> String {
        guard workout.discipline.isTrainingSession else {
            return workout.title
        }

        if let summary = WorkoutSummaryText.make(for: workout) {
            return "\(workout.title) · \(summary)"
        }

        return workout.title
    }
}

private struct JourneyWeekProjection: Identifiable {
    let id: Date
    let weekIndex: Int
    let startDate: Date
    let endDate: Date
    let phase: TrainingPhase
    let focus: String
    let sports: [Sport]
    let sessionCount: Int
    let isCurrent: Bool
    let isProjected: Bool
    let isRaceWeek: Bool

    var title: String {
        isRaceWeek ? "Race Week" : "Week \(weekIndex)"
    }

    var dateRange: String {
        TrainingFormatter.weekRange(start: startDate, end: endDate)
    }

    var sessionLabel: String {
        isProjected ? "≤\(sessionCount) sessions" : "\(sessionCount) sessions"
    }

    static func make(
        setup: AthleteSetup,
        plans: [WeeklyPlan],
        asOf today: Date = .now,
        calendar: Calendar = .current
    ) -> [JourneyWeekProjection] {
        guard let event = setup.objective.event,
              let eventDate = event.eventDate,
              eventDate >= calendar.startOfDay(for: today) else {
            return []
        }

        let currentWeekStart = startOfTrainingWeek(containing: today, calendar: calendar)
        let raceWeekStart = startOfTrainingWeek(containing: eventDate, calendar: calendar)
        let preferredSessions = max(
            1,
            min(
                setup.schedule.availableDays.count,
                setup.preferences.filter(\.isTrained).reduce(0) { $0 + $1.sessionsPerWeek }
            )
        )

        let planner = TrainingJourneyPlanner(calendar: calendar)
        var result: [JourneyWeekProjection] = []
        var cursor = currentWeekStart
        var index = 1

        while cursor <= raceWeekStart {
            let end = calendar.date(byAdding: .day, value: 6, to: cursor) ?? cursor
            let journey = planner.plan(setup: setup, plans: plans, asOf: cursor)
            let existingPlan = plans.first {
                $0.endDate >= cursor && $0.startDate <= end
            }
            let existingSessions = existingPlan?.prescribedTrainingSessions ?? []
            let isCurrent = calendar.isDate(today, inSameDayAs: cursor)
                || (today >= cursor && today <= end)
            let isRaceWeek = cursor == raceWeekStart

            let sports: [Sport]
            if !existingSessions.isEmpty {
                sports = Array(
                    Set(existingSessions.compactMap { $0.discipline.sport })
                ).sorted { $0.rawValue < $1.rawValue }
            } else {
                sports = journey.sportPriorities
                    .sorted { $0.rank < $1.rank }
                    .map(\.sport)
            }

            result.append(
                JourneyWeekProjection(
                    id: cursor,
                    weekIndex: index,
                    startDate: cursor,
                    endDate: min(end, eventDate),
                    phase: isRaceWeek ? .raceWeek : journey.phase,
                    focus: isRaceWeek
                        ? "Race day"
                        : (journey.primaryFocus?.kind.compactDisplayName ?? journey.phase.shortName),
                    sports: sports,
                    sessionCount: existingSessions.isEmpty ? preferredSessions : existingSessions.count,
                    isCurrent: isCurrent,
                    isProjected: existingSessions.isEmpty,
                    isRaceWeek: isRaceWeek
                )
            )

            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
            index += 1
        }

        return result
    }

    private static func startOfTrainingWeek(
        containing date: Date,
        calendar: Calendar
    ) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = Weekday(date: start, calendar: calendar) ?? .monday
        return calendar.date(
            byAdding: .day,
            value: -weekday.offsetFromMonday,
            to: start
        ) ?? start
    }
}

private extension TrainingPhase {
    var shortName: String {
        switch self {
        case .foundation: "Foundation"
        case .build: "Build"
        case .specific: "Race Specific"
        case .taper: "Taper"
        case .raceWeek: "Race Week"
        case .recovery: "Recovery"
        }
    }

    var symbolName: String {
        switch self {
        case .foundation: "circle.grid.2x2"
        case .build: "chart.line.uptrend.xyaxis"
        case .specific: "scope"
        case .taper: "arrow.down.right"
        case .raceWeek: "flag.checkered"
        case .recovery: "heart"
        }
    }

    func tint(theme: AtheviaTheme) -> Color {
        switch self {
        case .foundation:
            theme.color(.accent, classic: .blue)
        case .build:
            theme.color(.accent, classic: .orange)
        case .specific:
            theme.color(.accent, classic: .purple)
        case .taper:
            theme.color(.accent, classic: .teal)
        case .raceWeek:
            theme.color(.accent, classic: .green)
        case .recovery:
            theme.color(.accent, classic: .mint)
        }
    }
}

private extension TrainingPhase {
    var beginnerExplanation: String {
        switch self {
        case .foundation:
            "Build a steady base and get your body comfortable with regular training."
        case .build:
            "Gradually do a little more so you can handle longer or harder sessions."
        case .specific:
            "Practice workouts that are closer to what you will do on race day."
        case .taper:
            "Reduce training load before the race so you arrive rested but still sharp."
        case .raceWeek:
            "Keep training light and focus on being ready for race day."
        case .recovery:
            "Lower the workload so your body can recover before building again."
        }
    }
}

private extension String {
    var beginnerFocusExplanation: String {
        switch self {
        case "Endurance":
            "Build the ability to keep going comfortably for longer."
        case "Race pace":
            "Practice the effort you may use during your event."
        case "Run / walk":
            "Alternate running and walking to build running ability safely."
        case "Continuous run":
            "Run continuously for a manageable amount of time."
        case "Swim continuity":
            "Swim for longer stretches with fewer breaks."
        case "Swim technique":
            "Focus on smoother, more efficient swimming."
        case "Brick":
            "Practice cycling and then running, similar to a triathlon transition."
        case "Taper":
            "Train less so your body can recover before race day."
        case "Recovery":
            "Use easier activity to support recovery."
        case "Consistency":
            "Focus on completing regular training without adding too much too quickly."
        case "Race day":
            "This week is about arriving fresh and ready for your event."
        default:
            self
        }
    }
}

private extension WeeklyTrainingObjectiveKind {
    var compactDisplayName: String {
        switch self {
        case .runWalkContinuity: "Run / walk"
        case .continuousRunning: "Continuous run"
        case .endurance: "Endurance"
        case .swimContinuity: "Swim continuity"
        case .swimTechnique: "Swim technique"
        case .brickTransition: "Brick"
        case .racePacing: "Race pace"
        case .taper: "Taper"
        case .recovery: "Recovery"
        case .consistency: "Consistency"
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        Text("Race plan preview requires athlete setup")
    }
}
#endif
