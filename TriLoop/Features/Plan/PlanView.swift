import SwiftData
import SwiftUI

/// Date-led view of the plan: pick a day, see that day's session in full.
///
/// Replaces the week-list-plus-hidden-picker arrangement, where choosing a week
/// meant finding it behind an overflow menu.
struct PlanView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    @State private var selection: Date = .now
    @State private var isPresentingCalendar = false
    @State private var hasChosenOpeningDay = false

    private var allWorkouts: [PlannedWorkout] {
        plans.flatMap(\.orderedWorkouts).sorted { $0.date < $1.date }
    }

    private var selectedWorkout: PlannedWorkout? {
        allWorkouts.first { Calendar.current.isDate($0.date, inSameDayAs: selection) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allWorkouts.isEmpty {
                    ContentUnavailableView(
                        "No plan yet",
                        systemImage: "calendar",
                        description: Text("Your first training week has not been generated.")
                    )
                } else {
                    VStack(spacing: 0) {
                        DateStrip(workouts: allWorkouts, selection: $selection)

                        Divider()

                        if let workout = selectedWorkout {
                            WorkoutDayDetail(workout: workout)
                        } else {
                            ContentUnavailableView(
                                "Nothing planned",
                                systemImage: "moon.zzz",
                                description: Text("There is no session on this date.")
                            )
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingCalendar = true
                    } label: {
                        Label("Choose a date", systemImage: "calendar")
                    }
                }
            }
            .sheet(isPresented: $isPresentingCalendar) {
                calendarSheet
            }
            .onAppear(perform: selectSensibleDay)
        }
    }

    private var title: String {
        selection.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var calendarSheet: some View {
        DatePicker(
            "Date",
            selection: $selection,
            in: dateRange,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(.horizontal, 12)
        .onChange(of: selection) { isPresentingCalendar = false }
        .presentationDetents([.medium])
    }

    /// Bounded by the plan itself: there is nothing to show on a date TriLoop
    /// has never prescribed.
    private var dateRange: ClosedRange<Date> {
        let dates = allWorkouts.map(\.date)
        guard let first = dates.min(), let last = dates.max() else {
            return Date.now...Date.now
        }
        return first...max(last, first)
    }

    /// Opens on today when it is part of a plan, and on the nearest planned day
    /// otherwise, so the screen never starts empty. Runs once: `onAppear` fires
    /// again when a pushed screen is popped, which would discard the chosen day.
    private func selectSensibleDay() {
        guard !hasChosenOpeningDay, !allWorkouts.isEmpty else { return }
        hasChosenOpeningDay = true

        let calendar = Calendar.current
        if allWorkouts.contains(where: { calendar.isDateInToday($0.date) }) {
            selection = .now
            return
        }
        let now = Date.now
        let nearest = allWorkouts.min {
            abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now))
        }
        if let nearest { selection = nearest.date }
    }
}

#Preview {
    PlanView()
        .modelContainer(PreviewData.container)
}
