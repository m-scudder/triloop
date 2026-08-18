import SwiftData
import SwiftUI

struct TodayView: View {
    @Query(sort: \WeeklyPlan.startDate, order: .reverse) private var plans: [WeeklyPlan]

    @AppStorage("automaticallyScheduleWorkouts") private var automaticallySchedule = false
    @State private var isScheduling = false
    @State private var scheduleMessage: String?
    @State private var checkInWorkout: PlannedWorkout?
    @State private var activity: DailyActivity?
    @State private var hourlySteps: [SamplePoint] = []
    @State private var samples: WorkoutSamples?
    @State private var activityFailure: String?
    @AppStorage("simulateHealthSamples") private var simulateSamples = false
    @Environment(\.scenePhase) private var scenePhase

    private let health = HealthKitWorkoutImporter()

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
            // Steps keep accruing while the app is open, so the card re-reads
            // HealthKit rather than showing whatever was true on launch.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await loadActivity()
                    try? await Task.sleep(for: .seconds(60))
                }
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

    /// All-day movement, shown as context rather than a target. TriLoop sets no
    /// step goal: the plan decides the training, and steps are what else happened.
    private func dailyActivity(_ activity: DailyActivity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "All day")

            NavigationLink {
                ActivityDetailView()
            } label: {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 8) {
                            if let steps = activity.steps {
                                StatTile(value: steps.formatted(.number), label: "Steps")
                            }
                            if let distance = activity.distanceMeters, distance > 0 {
                                StatTile(
                                    value: TrainingFormatter.distance(meters: distance),
                                    label: "Walk + run"
                                )
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        if hourlySteps.contains(where: { $0.value > 0 }) {
                            HourlyStepsChart(points: hourlySteps)
                        }

                        if let activityFailure {
                            Text(activityFailure)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func loadActivity() async {
        let todaysWorkout = plans.currentPlan().flatMap { plan in
            TodayFocus.resolve(plan: plan).workoutID.flatMap { id in
                plan.orderedWorkouts.first { $0.id == id }
            }
        }

        #if DEBUG
        if simulateSamples {
            if let todaysWorkout, todaysWorkout.isCompleted {
                samples = SimulatedWorkoutSamples.make(for: todaysWorkout)
            }
            activity = DailyActivity(steps: 8_412, distanceMeters: 6_240)
            hourlySteps = SimulatedDailySteps.today()
            return
        }
        #endif

        switch await health.authorizationStatus {
        case .unavailable:
            activityFailure = "Health data isn't available on this device."
            return
        case .notDetermined, .denied:
            activityFailure = "Connect Apple Health in Settings to see your daily movement."
            return
        case .authorized:
            break
        }

        do {
            activity = try await health.dailyActivity(on: .now)
            hourlySteps = try await health.hourlySteps(on: .now)
            activityFailure = nil
        } catch {
            activityFailure = "Could not read today's steps: \(error.localizedDescription)"
        }

        if let summary = todaysWorkout?.importedSummary {
            samples = try? await health.samples(forWorkout: summary.healthKitUUID)
        }
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
                        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.separator, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let workout = focusedWorkout {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(text: eyebrow(for: focus.kind))
                        FocusWorkoutCard(workout: workout)
                    }

                    // Once today's session is in, the day's detail belongs here
                    // rather than behind another tap.
                    if let summary = workout.importedSummary {
                        RecordedWorkoutView(workout: workout, summary: summary)
                    }

                    if let samples, !samples.isEmpty {
                        WorkoutChartsView(
                            discipline: workout.discipline,
                            samples: samples,
                            summary: workout.importedSummary
                        )
                    }
                } else {
                    Text("This week is complete. Generate the next one when you're ready.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if let activity, activity.hasAnything {
                    dailyActivity(activity)
                } else if activityFailure != nil {
                    dailyActivity(DailyActivity())
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

/// High-contrast hero for the session in focus, coloured by its sport so the
/// screen reads differently on a run day and a swim day.
private struct FocusWorkoutCard: View {
    let workout: PlannedWorkout

    private var surface: Color { workout.discipline.surface }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: workout.discipline.symbolName)
                    .font(.headline)
                    .foregroundStyle(surface)
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
                    .foregroundStyle(surface)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(workout.discipline.gradient, in: .rect(cornerRadius: 16))
        .shadow(color: surface.opacity(0.35), radius: 12, y: 6)
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
