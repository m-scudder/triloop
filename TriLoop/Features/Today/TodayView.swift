import SwiftData
import SwiftUI

struct TodayView: View {
    @Query(sort: \WeeklyPlan.startDate, order: .reverse) private var plans: [WeeklyPlan]

    @AppStorage("automaticallyScheduleWorkouts") private var automaticallySchedule = false
    @State private var isScheduling = false
    @State private var scheduleMessage: String?
    @State private var checkInWorkout: PlannedWorkout?

    var body: some View {
        NavigationStack {
            Group {
                if let plan = plans.currentPlan() {
                    content(for: plan)
                } else {
                    ContentUnavailableView(
                        "No plan yet",
                        systemImage: "calendar",
                        description: Text("Your first training week has not been generated.")
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let plan = plans.currentPlan() {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            sendWeekToWatch(plan)
                        } label: {
                            Label("Send week to Apple Watch", systemImage: "applewatch")
                        }
                        .disabled(isScheduling)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let scheduleMessage {
                    Text(scheduleMessage)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: .rect(cornerRadius: 12))
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: scheduleMessage)
            .sheet(item: $checkInWorkout) { workout in
                RecoveryCheckInSheet(workout: workout)
            }
            .task {
                guard automaticallySchedule, let plan = plans.currentPlan() else { return }
                await autoScheduleIfPermitted(plan)
            }
        }
    }

    private func sendWeekToWatch(_ plan: WeeklyPlan) {
        isScheduling = true
        Task {
            defer { isScheduling = false }
            let outcome = await WeekScheduler().scheduleWeek(plan)
            scheduleMessage = message(for: outcome)
        }
    }

    /// Never prompts. Automatic scheduling stays silent until the athlete has
    /// already granted permission through the explicit action.
    private func autoScheduleIfPermitted(_ plan: WeeklyPlan) async {
        let scheduler = WorkoutKitScheduler()
        guard await scheduler.authorizationState() == .authorized else { return }
        _ = await WeekScheduler(scheduler: scheduler).scheduleWeek(plan)
    }

    private func message(for outcome: WeekScheduler.Outcome) -> String {
        if outcome.added > 0 {
            let sessions = outcome.added == 1 ? "session" : "sessions"
            return "Added \(outcome.added) \(sessions) to your Watch."
        }
        if outcome.alreadyScheduled > 0 {
            return "This week is already on your Watch."
        }
        if outcome.failed > 0 {
            return "Could not reach your Apple Watch."
        }
        return "Nothing left to schedule this week."
    }

    private func content(for plan: WeeklyPlan) -> some View {
        let focus = TodayFocus.resolve(plan: plan)
        let focusedWorkout = focus.workoutID.flatMap { id in
            plan.orderedWorkouts.first { $0.id == id }
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subtitle(plan: plan, focus: focus))
                        .font(.title2.weight(.semibold))
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let pending = plan.sessionAwaitingCheckIn() {
                    Button {
                        checkInWorkout = pending
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sun.horizon")
                            Text("How do you feel after yesterday?")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                        .padding(12)
                        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                if let workout = focusedWorkout {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(text: eyebrow(for: focus.kind))
                        FocusWorkoutCard(workout: workout)
                    }
                } else {
                    Text("This week is complete. Generate the next one when you're ready.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionEyebrow(text: "This week")

                    Card(padding: 4) {
                        VStack(spacing: 0) {
                            ForEach(plan.orderedWorkouts, id: \.id) { workout in
                                NavigationLink {
                                    WorkoutDetailView(workout: workout)
                                } label: {
                                    WorkoutRow(
                                        workout: workout,
                                        isToday: Calendar.current.isDateInToday(workout.date)
                                    )
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)

                                if workout.id != plan.orderedWorkouts.last?.id {
                                    Divider().padding(.leading, 10)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func eyebrow(for kind: TodayFocus.Kind) -> String {
        switch kind {
        case .today: "Today's workout"
        case .upcoming: "Up next"
        case .weekComplete: "Week complete"
        }
    }

    private func subtitle(plan: WeeklyPlan, focus: TodayFocus) -> String {
        guard let dayNumber = focus.dayNumber else {
            return "Week \(plan.weekNumber)"
        }
        return "Week \(plan.weekNumber) · Day \(dayNumber)"
    }
}

/// High-contrast hero for the session in focus. The only filled surface on the
/// screen, so the eye lands on today's workout before anything else.
private struct FocusWorkoutCard: View {
    let workout: PlannedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: workout.discipline.symbolName)
                    .font(.headline)
                    .foregroundStyle(Color.focusSurface)
                    .frame(width: 36, height: 36)
                    .background(Color.onFocusSurface, in: .circle)

                Text(workout.title)
                    .font(.headline)
                    .foregroundStyle(Color.onFocusSurface)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if let summary = WorkoutSummaryText.make(for: workout) {
                    Text(summary)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.onFocusSurface.opacity(0.85))
                }
            }

            if intervalRows.isEmpty == false || workout.targetRPE != nil {
                HStack(alignment: .center, spacing: 14) {
                    if let count = repeatCount {
                        Text("\(count) ×")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.onFocusSurface)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(intervalRows, id: \.self) { row in
                            Text(row)
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(Color.onFocusSurface)
                        }
                    }

                    Spacer(minLength: 0)

                    if let rpe = workout.targetRPE {
                        Text("RPE \(TrainingFormatter.rpe(rpe))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.onFocusSurface.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.onFocusSurface.opacity(0.16), in: .capsule)
                    }
                }
            }

            NavigationLink {
                WorkoutDetailView(workout: workout)
            } label: {
                Text("View Workout")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.onFocusSurface, in: .rect(cornerRadius: 10))
                    .foregroundStyle(Color.focusSurface)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.focusSurface, in: .rect(cornerRadius: 16))
        // Keeps the card distinct from a near-black background in dark mode.
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.onFocusSurface.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var repeatCount: Int? {
        workout.orderedSteps.first { $0.kind == .repeatBlock }?.repeatCount
    }

    /// One line per interval child, e.g. "1:15 Run" then "2:00 Walk".
    private var intervalRows: [String] {
        guard let block = workout.orderedSteps.first(where: { $0.kind == .repeatBlock }) else {
            return []
        }
        return block.orderedChildren.compactMap { child in
            guard let seconds = child.durationSeconds else { return nil }
            return "\(TrainingFormatter.intervalDuration(seconds: seconds))  \(child.title)"
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(PreviewData.container)
}
