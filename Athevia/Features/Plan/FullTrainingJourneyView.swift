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

                        Text(week.phase.shortName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(week.phase.tint(theme: theme))
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

                            if week.isProjected {
                                Spacer()
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(AtheviaAdaptiveStyle(.tertiary, gaming: .secondaryText))
                                    .accessibilityLabel("Projected")
                            }
                        }
                    }
                }
            }
        }
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
