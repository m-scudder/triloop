import SwiftData
import SwiftUI

/// Date-led view of the plan: pick a day, see the session that matters.
///
/// The plan is for orientation, so it shows a concise session summary. The full
/// prescription, analysis and management actions remain one tap away.
struct PlanView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    @State private var selection: Date = .now
    @State private var isPresentingCalendar = false
    @State private var hasChosenOpeningDay = false
    /// Which session is shown when a day holds more than one.
    @State private var focused: UUID?

    private var allWorkouts: [PlannedWorkout] {
        plans.flatMap(\.orderedWorkouts).sorted { $0.date < $1.date }
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
                            PlanSessionSummary(workout: workout)
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

private struct PlanSessionSummary: View {
    let workout: PlannedWorkout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    DisciplineBadge(discipline: workout.discipline, size: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.title)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)

                        if let summary = WorkoutSummaryText.make(for: workout) {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                if let status {
                    Label(status.title, systemImage: status.symbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(status.tint)
                }

                if workout.isCompleted {
                    completedSummary
                }

                if let structure = WorkoutStructureSummary.text(for: workout) {
                    Text(structure)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if workout.orderedSteps.isEmpty {
                    Text("Nothing is scheduled. Rest is part of the plan.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    WorkoutDetailView(workout: workout)
                } label: {
                    HStack {
                        Text(workout.discipline.isTrainingSession ? "View workout" : "View details")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var completedSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let actual = workout.importedSummary?.duration,
               let planned = workout.estimatedDurationSeconds {
                Text("Planned \(TrainingFormatter.totalDuration(seconds: planned)) · Actual \(TrainingFormatter.totalDuration(seconds: actual))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let actual = workout.importedSummary?.duration {
                Text("Actual \(TrainingFormatter.totalDuration(seconds: actual))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let effort = workout.feedback?.rpe {
                Text("Effort \(effort)/10")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    private var status: (title: String, symbol: String, tint: Color)? {
        if workout.awaitingFeedback {
            return ("Add your report", "exclamationmark.circle.fill", .orange)
        }
        if workout.status == .completed {
            return ("Completed", "checkmark.circle.fill", .green)
        }
        if workout.isSkipped {
            return ("Skipped", "slash.circle.fill", .secondary)
        }
        if workout.isMissed() {
            return ("Not completed", "exclamationmark.circle.fill", .orange)
        }
        if Calendar.current.isDateInToday(workout.date) {
            return ("Today", "circle.fill", workout.discipline.tint)
        }
        return nil
    }
}

#if DEBUG
#Preview {
    PlanView()
        .modelContainer(PreviewData.container)
}
#endif
