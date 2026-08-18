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
        let id: Date
        let days: [PlannedWorkout]
    }

    private var weeks: [Week] {
        let grouped = Dictionary(grouping: workouts) { workout in
            calendar.dateInterval(of: .weekOfYear, for: workout.date)?.start
                ?? calendar.startOfDay(for: workout.date)
        }
        return grouped
            .map { Week(id: $0.key, days: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(weeks) { week in
                        HStack(spacing: 6) {
                            ForEach(week.days, id: \.id) { workout in
                                day(workout)
                                    .onTapGesture { selection = workout.date }
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

    private func day(_ workout: PlannedWorkout) -> some View {
        let isSelected = calendar.isDate(workout.date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(workout.date)
        let tint = workout.discipline.tint

        return VStack(spacing: 6) {
            Text(TrainingFormatter.weekdayInitial(for: workout.date))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .secondary)

            Image(systemName: workout.discipline.symbolName)
                .font(.footnote)
                .foregroundStyle(isSelected ? .white : tint)

            Circle()
                .fill(workout.hasReport ? (isSelected ? Color.white : .green) : .clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(workout.discipline.gradient) : AnyShapeStyle(tint.opacity(0.10)))
        }
        .overlay {
            if isToday, !isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1.5)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(workout.date.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(workout.title)"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
