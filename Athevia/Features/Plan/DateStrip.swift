import SwiftData
import SwiftUI

/// Week-by-week day picker.
///
/// Paged rather than free-scrolling: a training week is the unit the plan is
/// built and reasoned about in, so a swipe moves a whole week rather than
/// leaving days from two weeks side by side.
struct DateStrip: View {
    @Environment(\.atheviaTheme) private var theme

    let workouts: [PlannedWorkout]
    @Binding var selection: Date
    var calendar: Calendar = .current

    private struct Week: Identifiable {
        let id: Date
        let start: Date
        let days: [Day]
    }

    /// One tile per calendar day. Empty days are kept so every page is a stable
    /// seven-day week even when the athlete only has one historical workout.
    private struct Day: Identifiable {
        let id: Date
        let workouts: [PlannedWorkout]

        var date: Date { id }

        /// Training leads over recovery/rest when more than one item shares a day.
        var representative: PlannedWorkout? {
            workouts.first { $0.discipline.isTrainingSession } ?? workouts.first
        }

        /// The day's sports in swim, bike, run order, so a brick day always
        /// reads the same way round.
        var sports: [Sport] {
            let present = Set(workouts.compactMap(\.discipline.sport))
            return [.swimming, .cycling, .running].filter(present.contains)
        }
    }

    /// A single continuous calendar across planned sessions and imported Health
    /// history. Standalone workouts from before the current plan must remain
    /// reachable after reset/re-onboarding, so pages can no longer be derived
    /// only from `WeeklyPlan` relationships.
    private var weeks: [Week] {
        guard let firstWorkout = workouts.min(by: { $0.date < $1.date }),
              let lastWorkout = workouts.max(by: { $0.date < $1.date }) else {
            return []
        }

        let firstWeek = mondayStart(for: firstWorkout.date)
        let lastWeek = mondayStart(for: lastWorkout.date)
        var result: [Week] = []
        var weekStart = firstWeek

        while weekStart <= lastWeek {
            let days = (0..<7).map { offset -> Day in
                let date = calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: weekStart
                ) ?? weekStart

                let startOfDay = calendar.startOfDay(for: date)
                let onDay = workouts
                    .filter {
                        calendar.isDate(
                            $0.date,
                            inSameDayAs: startOfDay
                        )
                    }
                    .sorted { lhs, rhs in
                        if lhs.origin != rhs.origin {
                            return lhs.origin != .imported
                        }
                        return (lhs.completedAt ?? lhs.date)
                            < (rhs.completedAt ?? rhs.date)
                    }

                return Day(
                    id: startOfDay,
                    workouts: onDay
                )
            }

            result.append(
                Week(
                    id: weekStart,
                    start: weekStart,
                    days: days
                )
            )

            guard let next = calendar.date(
                byAdding: .day,
                value: 7,
                to: weekStart
            ) else {
                break
            }
            weekStart = next
        }

        return result
    }

    /// Training weeks are Monday–Sunday regardless of the device locale.
    private func mondayStart(for date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(
            byAdding: .day,
            value: -daysFromMonday,
            to: day
        ) ?? day
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(weeks) { week in
                        HStack(spacing: 6) {
                            ForEach(week.days) { day in
                                tile(day)
                            }
                        }
                        .padding(.horizontal, 16)
                        .containerRelativeFrame(.horizontal)
                        .id(week.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: selection) { scroll(proxy, animated: true) }
        }
        // Constrains the whole component: the ScrollView, and the
        // ScrollViewReader wrapping it, otherwise take every point of vertical
        // space offered and centre the row inside it.
        .frame(height: 78)
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let week = weeks.first(where: { week in
            week.days.contains { calendar.isDate($0.date, inSameDayAs: selection) }
        }) else { return }

        if animated {
            withAnimation(.snappy) { proxy.scrollTo(week.id, anchor: .center) }
        } else {
            proxy.scrollTo(week.id, anchor: .center)
        }
    }

    private func tile(_ day: Day) -> some View {
        let workout = day.representative
        let isSelected = calendar.isDate(
            day.date,
            inSameDayAs: selection
        )
        let isToday = calendar.isDateInToday(day.date)
        let isSkipped = !day.workouts.isEmpty
            && day.workouts.allSatisfy(\.isSkipped)
        let tint = day.sports.first?.discipline.themedTint(theme)
            ?? workout?.discipline.themedTint(theme)
            ?? .secondary

        return VStack(spacing: 6) {
            Text(
                TrainingFormatter.weekdayInitial(
                    for: day.date
                )
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(
                isSelected
                    ? tint
                    : .secondary.opacity(0.72)
            )

            icons(
                for: day,
                isSelected: isSelected,
                isSkipped: isSkipped
            )

            Circle()
                .fill(
                    marker(
                        for: day,
                        isSelected: isSelected
                    )
                )
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .fill(
                background(
                    for: day,
                    isSelected: isSelected
                )
            )
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .strokeBorder(
                isSelected
                    ? tint
                    : isToday
                        ? tint.opacity(0.75)
                        : .clear,
                lineWidth: isSelected ? 2 : 1.5
            )
        }
        .opacity(
            isSelected
                ? 1
                : day.workouts.isEmpty
                    ? 0.36
                    : isSkipped
                        ? 0.42
                        : 0.72
        )
        .contentShape(.rect)
        .onTapGesture {
            selection = day.date
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label(for: day))
        .accessibilityAddTraits(
            isSelected ? [.isSelected] : []
        )
    }

    /// One glyph per sport, so a brick day reads as both rather than as whichever
    /// session happens to be first.
    @ViewBuilder
    private func icons(
        for day: Day,
        isSelected: Bool,
        isSkipped: Bool
    ) -> some View {
        let sports = day.sports

        if day.workouts.isEmpty {
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.24))
                .frame(height: 16)
        } else if isSkipped || sports.isEmpty {
            let discipline = day.representative?.discipline
            let tint = discipline?.themedTint(theme)
                ?? Color.secondary

            Image(
                systemName: isSkipped
                    ? "slash.circle"
                    : discipline?.symbolName ?? "circle"
            )
            .font(.footnote)
            .foregroundStyle(
                isSelected
                    ? tint
                    : isSkipped
                        ? Color.secondary.opacity(0.55)
                        : tint.opacity(0.45)
            )
            .frame(height: 16)
        } else {
            HStack(spacing: 2) {
                ForEach(sports, id: \.self) { sport in
                    Image(systemName: sport.discipline.symbolName)
                        .font(
                            sports.count > 2
                                ? .caption2
                                : .footnote
                        )
                        .foregroundStyle(
                            isSelected
                                ? AnyShapeStyle(
                                    sport.discipline.themedTint(theme)
                                )
                                : AnyShapeStyle(
                                    sport.discipline
                                        .themedTint(theme)
                                        .opacity(0.45)
                                )
                        )
                }
            }
            .frame(height: 16)
        }
    }

    /// A day carries its sports' colours, so the tile matches the glyphs on it.
    ///
    /// Multi-sport days blend the deeper stop of each hue rather than the
    /// lighter one, so white glyphs hold up across the whole tile.
    private func background(for day: Day, isSelected: Bool) -> AnyShapeStyle {
        let sports = day.sports

        guard sports.count > 1 else {
            let tint = day.representative?.discipline.themedTint(theme)
                ?? Color.secondary
            return AnyShapeStyle(
                tint.opacity(
                    isSelected
                        ? 0.16
                        : day.workouts.isEmpty
                            ? 0.02
                            : 0.045
                )
            )
        }

        let colours = sports.map {
            $0.discipline.themedSurface(theme).opacity(isSelected ? 0.18 : 0.055)
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: colours,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func label(for day: Day) -> String {
        let date = TrainingFormatter.shortDate(day.date)
        guard let representative = day.representative else {
            return "\(date), no workout"
        }

        let titles = day.workouts
            .map(\.title)
            .joined(separator: ", ")
        return "\(date), \(titles)\(stateLabel(for: representative))"
    }

    private func marker(
        for day: Day,
        isSelected: Bool
    ) -> Color {
        guard let representative = day.representative else {
            return .clear
        }

        if day.workouts.contains(where: \.hasReport) {
            return isSelected
                ? representative.discipline.themedTint(theme)
                : .green
        }

        if day.workouts.contains(
            where: { $0.isMissed(calendar: calendar) }
        ) {
            return isSelected
                ? representative.discipline.themedTint(theme)
                : .orange
        }

        if day.workouts.contains(
            where: {
                $0.origin == .imported
                    && $0.isCompleted
            }
        ) {
            return isSelected
                ? representative.discipline.themedTint(theme)
                : representative.discipline
                    .themedTint(theme)
                    .opacity(0.65)
        }

        return .clear
    }

    private func stateLabel(for workout: PlannedWorkout) -> String {
        if workout.isSkipped { return ", skipped" }
        if workout.hasReport { return ", reported" }
        if workout.isMissed(calendar: calendar) { return ", missed" }
        return ""
    }
}
