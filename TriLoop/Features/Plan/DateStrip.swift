import SwiftData
import SwiftUI

/// Week-by-week day picker.
///
/// Paged rather than free-scrolling: a training week is the unit the plan is
/// built and reasoned about in, so a swipe moves a whole week rather than
/// leaving days from two weeks side by side.
struct DateStrip: View {
    let workouts: [PlannedWorkout]
    @Binding var selection: Date
    var calendar: Calendar = .current

    private struct Week: Identifiable {
        let id: PersistentIdentifier
        let start: Date
        let days: [Day]
    }

    /// One tile per day, not per workout: a day can hold more than one session
    /// once the athlete adds their own alongside the plan.
    private struct Day: Identifiable {
        let id: Date
        let workouts: [PlannedWorkout]

        var date: Date { id }

        /// What the tile shows. Training leads, so a session added to a rest day
        /// is not represented by the rest placeholder.
        var representative: PlannedWorkout {
            workouts.first { $0.discipline.isTrainingSession } ?? workouts[0]
        }

        /// The day's sports in swim, bike, run order, so a brick day always
        /// reads the same way round.
        var sports: [Sport] {
            let present = Set(workouts.compactMap(\.discipline.sport))
            return [.swimming, .cycling, .running].filter(present.contains)
        }
    }

    /// Grouped by the plan each day belongs to, not by `.weekOfYear`: the plan
    /// runs Monday to Sunday, while the calendar's week starts on whichever day
    /// the locale says, which splits a training week across two pages.
    ///
    /// Keyed on the plan itself rather than its start date, so two plans that
    /// somehow share a date stay separate pages instead of merging into one
    /// fourteen-day strip.
    private var weeks: [Week] {
        let grouped = Dictionary(grouping: workouts.filter { $0.plan != nil }) { $0.plan!.persistentModelID }

        return grouped.compactMap { id, workouts -> Week? in
            guard let start = workouts.first?.plan?.startDate else { return nil }

            let days = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.date) }
                .map { Day(id: $0.key, workouts: $0.value.sorted { $0.date < $1.date }) }
                .sorted { $0.date < $1.date }

            return Week(id: id, start: start, days: days)
        }
        .sorted { $0.start < $1.start }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(weeks) { week in
                        HStack(spacing: 6) {
                            ForEach(week.days) { day in
                                tile(day)
                                    .onTapGesture { selection = day.date }
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
        let isSelected = calendar.isDate(day.date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day.date)
        let isSkipped = day.workouts.allSatisfy(\.isSkipped)
        // Matches the first stop of the tile's gradient rather than whichever
        // session happens to be first in the day.
        let tint = day.sports.first?.discipline.tint ?? workout.discipline.tint

        return VStack(spacing: 6) {
            Text(TrainingFormatter.weekdayInitial(for: day.date))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .secondary)

            icons(for: day, isSelected: isSelected, isSkipped: isSkipped)

            Circle()
                .fill(marker(for: day, isSelected: isSelected))
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(background(for: day, isSelected: isSelected))
        }
        .overlay {
            if isToday, !isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1.5)
            }
        }
        .opacity(isSkipped && !isSelected ? 0.55 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label(for: day))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// One glyph per sport, so a brick day reads as both rather than as whichever
    /// session happens to be first.
    @ViewBuilder
    private func icons(for day: Day, isSelected: Bool, isSkipped: Bool) -> some View {
        let sports = day.sports

        if isSkipped || sports.isEmpty {
            Image(systemName: isSkipped ? "slash.circle" : day.representative.discipline.symbolName)
                .font(.footnote)
                .foregroundStyle(isSelected ? .white : (isSkipped ? Color.secondary : day.representative.discipline.tint))
                .frame(height: 16)
        } else {
            HStack(spacing: 2) {
                ForEach(sports, id: \.self) { sport in
                    Image(systemName: sport.discipline.symbolName)
                        // Three glyphs have to fit the same tile as one.
                        .font(sports.count > 2 ? .caption2 : .footnote)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(sport.discipline.tint))
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
            let discipline = day.representative.discipline
            return isSelected
                ? AnyShapeStyle(discipline.gradient)
                : AnyShapeStyle(discipline.tint.opacity(0.10))
        }

        let colours = sports.map(\.discipline.surface)
        return AnyShapeStyle(
            LinearGradient(
                colors: isSelected ? colours : colours.map { $0.opacity(0.14) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func label(for day: Day) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let titles = day.workouts.map(\.title).joined(separator: ", ")
        return "\(date), \(titles)\(stateLabel(for: day.representative))"
    }

    private func marker(for day: Day, isSelected: Bool) -> Color {
        if day.workouts.contains(where: \.hasReport) { return isSelected ? .white : .green }
        if day.workouts.contains(where: { $0.isMissed(calendar: calendar) }) {
            return isSelected ? .white : .orange
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
