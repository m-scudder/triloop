import SwiftData
import SwiftUI

/// Date-led view of the plan: pick a day and work with that session in place.
///
/// Home owns workout execution. Plan owns prescription, completed analysis and
/// schedule management, so there is no extra workout-detail navigation step.
struct PlanView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    @State private var selection: Date = .now
    @State private var isPresentingCalendar = false
    @State private var hasChosenOpeningDay = false
    @State private var focused: UUID?

    /// Plan contains prescribed sessions only. Health activities that could not
    /// be matched to a prescription remain available in workout history and
    /// analytics, but must not appear as a second "Recorded <sport>" Plan tab.
    private var allWorkouts: [PlannedWorkout] {
        plans
            .flatMap(\.orderedWorkouts)
            .filter { $0.origin != .imported }
            .sorted { $0.date < $1.date }
    }

    private var workoutsOnSelectedDay: [PlannedWorkout] {
        allWorkouts.filter { Calendar.current.isDate($0.date, inSameDayAs: selection) }
    }

    private var selectedWorkout: PlannedWorkout? {
        let onTheDay = workoutsOnSelectedDay
        return onTheDay.first { $0.id == focused } ?? onTheDay.first
    }

    private var sessionBinding: Binding<UUID?> {
        Binding(
            get: { selectedWorkout?.id },
            set: { focused = $0 }
        )
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

                        if workoutsOnSelectedDay.count > 1 {
                            Picker("Session", selection: sessionBinding) {
                                ForEach(workoutsOnSelectedDay) { workout in
                                    Text(workout.title).tag(workout.id)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }

                        if let workout = selectedWorkout {
                            WorkoutDayDetail(
                                workout: workout,
                                showsManagementMenu: true
                            )
                            .id(workout.id)
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
                    NavigationLink {
                        WorkoutLibraryView()
                    } label: {
                        Label("Workouts", systemImage: "square.grid.2x2")
                    }
                }
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

    private var dateRange: ClosedRange<Date> {
        let dates = allWorkouts.map(\.date)
        guard let first = dates.min(), let last = dates.max() else {
            return Date.now...Date.now
        }
        return first...max(last, first)
    }

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

#if DEBUG
#Preview {
    PlanView()
        .modelContainer(PreviewData.container)
}
#endif
