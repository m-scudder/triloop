import SwiftData
import SwiftUI

/// Date-led view of the plan: understand the week at a glance, then pick a day
/// to see the session that matters.
///
/// The plan is for orientation, so it keeps weekly context compact and the
/// selected session concise. Full prescription, analysis and management actions
/// remain one tap away.
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

    private var selectedPlan: WeeklyPlan? {
        plans.first { $0.contains(selection) }
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
                        if let selectedPlan {
                            PlanWeekSnapshot(plan: selectedPlan)
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                                .padding(.bottom, 12)
                        }

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

private struct PlanWeekSnapshot: View {
    let plan: WeeklyPlan

    private var sessions: [PlannedWorkout] { plan.trainingSessions }

    private var completedCount: Int {
        sessions.filter(\.isCompleted).count
    }

    private var plannedSeconds: TimeInterval {
        sessions.compactMap(\.estimatedDurationSeconds).reduce(0, +)
    }

    private var activeSports: [Sport] {
        Sport.allCases.filter { sport in
            sessions.contains { $0.discipline.sport == sport }
        }
    }

    private var focus: String? {
        if let reason = plan.generationReasonCode {
            return reason.displayName
        }
        let reason = plan.generationReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? nil : reason
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Week \(plan.weekNumber)")
                            .font(.headline)
                        Text(TrainingFormatter.weekRange(start: plan.startDate, end: plan.endDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(TrainingFormatter.totalDuration(seconds: plannedSeconds)) planned")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(completedCount) of \(sessions.count) completed")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: progress)
                        .tint(.accentColor)
                }

                if !activeSports.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(activeSports, id: \.rawValue) { sport in
                            sportSummary(sport)
                        }
                    }
                }

                if let focus {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Focus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(focus)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var progress: Double {
        guard !sessions.isEmpty else { return 0 }
        return Double(completedCount) / Double(sessions.count)
    }

    private func sportSummary(_ sport: Sport) -> some View {
        let sportSessions = sessions.filter { $0.discipline.sport == sport }
        let duration = sportSessions.compactMap(\.estimatedDurationSeconds).reduce(0, +)

        return HStack(spacing: 6) {
            Image(systemName: sport.discipline.symbolName)
                .foregroundStyle(sport.discipline.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(sport.discipline.displayName)
                    .font(.caption.weight(.medium))
                Text("\(sportSessions.count) · \(TrainingFormatter.totalDuration(seconds: duration))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
