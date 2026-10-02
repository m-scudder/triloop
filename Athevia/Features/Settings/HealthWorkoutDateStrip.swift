import SwiftUI

/// Weekly calendar strip for Apple Health history. Only the three sports Athevia
/// trains are represented so the visual language stays consistent with Plan.
struct HealthWorkoutDateStrip: View {
    @Environment(\.atheviaTheme) private var theme

    let records: [HealthWorkoutRecord]
    @Binding var selection: Date
    var calendar: Calendar = .current

    private struct Week: Identifiable {
        let id: Date
        let days: [Day]
    }

    private struct Day: Identifiable {
        let id: Date
        let records: [HealthWorkoutRecord]

        var date: Date { id }

        var sports: [Sport] {
            let present = Set(records.compactMap { $0.sport?.rawValue })
            return [.running, .cycling, .swimming].filter {
                present.contains($0.rawValue)
            }
        }
    }

    private var trainedRecords: [HealthWorkoutRecord] {
        records.filter { $0.sport != nil }
    }

    private var weeks: [Week] {
        guard let first = trainedRecords.map(\.start).min(),
              let last = trainedRecords.map(\.start).max() else {
            return []
        }

        let firstDay = calendar.startOfDay(for: first)
        let lastDay = calendar.startOfDay(for: last)
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: firstDay)?.start
            ?? firstDay
        let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay)?.start
            ?? lastDay

        var result: [Week] = []
        var weekStart = firstWeek

        while weekStart <= lastWeek {
            let days = (0..<7).map { offset -> Day in
                let date = calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: weekStart
                ) ?? weekStart

                let onDay = trainedRecords.filter {
                    calendar.isDate($0.start, inSameDayAs: date)
                }

                return Day(id: calendar.startOfDay(for: date), records: onDay)
            }

            result.append(Week(id: weekStart, days: days))
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(weeks) { week in
                        HStack(spacing: 6) {
                            ForEach(week.days) { day in
                                tile(day)
                                    .onTapGesture {
                                        selection = day.date
                                    }
                            }
                        }
                        .padding(.horizontal, 4)
                        .containerRelativeFrame(.horizontal)
                        .id(week.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .onAppear {
                scroll(proxy, animated: false)
            }
            .onChange(of: selection) {
                scroll(proxy, animated: true)
            }
        }
        .frame(height: 78)
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let week = weeks.first(where: { week in
            week.days.contains {
                calendar.isDate($0.date, inSameDayAs: selection)
            }
        }) else {
            return
        }

        if animated {
            withAnimation(.snappy) {
                proxy.scrollTo(week.id, anchor: .center)
            }
        } else {
            proxy.scrollTo(week.id, anchor: .center)
        }
    }

    private func tile(_ day: Day) -> some View {
        let isSelected = calendar.isDate(day.date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day.date)
        let tint = day.sports.first?.discipline.themedTint(theme) ?? .secondary

        return VStack(spacing: 6) {
            Text(TrainingFormatter.weekdayInitial(for: day.date))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(
                    isSelected
                        ? tint
                        : Color.secondary.opacity(0.72)
                )

            icons(for: day, selected: isSelected)

            Circle()
                .fill(day.records.isEmpty ? Color.clear : tint.opacity(isSelected ? 1 : 0.55))
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(background(for: day, selected: isSelected))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? tint
                        : isToday
                            ? tint.opacity(0.65)
                            : .clear,
                    lineWidth: isSelected ? 2 : 1.5
                )
        }
        .opacity(day.records.isEmpty ? 0.42 : (isSelected ? 1 : 0.72))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: day))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func icons(for day: Day, selected: Bool) -> some View {
        if day.sports.isEmpty {
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.28))
                .frame(height: 16)
        } else {
            HStack(spacing: 2) {
                ForEach(day.sports, id: \.self) { sport in
                    Image(systemName: sport.discipline.symbolName)
                        .font(day.sports.count > 2 ? .caption2 : .footnote)
                        .foregroundStyle(
                            selected
                                ? sport.discipline.themedTint(theme)
                                : sport.discipline.themedTint(theme).opacity(0.45)
                        )
                }
            }
            .frame(height: 16)
        }
    }

    private func background(
        for day: Day,
        selected: Bool
    ) -> AnyShapeStyle {
        guard day.sports.count > 1 else {
            let tint = day.sports.first?.discipline.themedTint(theme)
                ?? Color.secondary
            return AnyShapeStyle(
                tint.opacity(selected ? 0.16 : 0.045)
            )
        }

        let colours = day.sports.map {
            $0.discipline.themedSurface(theme)
                .opacity(selected ? 0.18 : 0.055)
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: colours,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func accessibilityLabel(for day: Day) -> String {
        let date = TrainingFormatter.shortDate(day.date)
        guard !day.sports.isEmpty else {
            return "\(date), no Run, Cycle or Swim workout"
        }

        let names = day.sports.map { $0.discipline.displayName }
            .joined(separator: ", ")
        return "\(date), \(names)"
    }
}
