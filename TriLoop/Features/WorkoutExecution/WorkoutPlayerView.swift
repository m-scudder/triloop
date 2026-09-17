import Combine
import SwiftUI

/// Executes the exact prescription already stored on the workout.
/// Opening this screen starts execution immediately; there is no second
/// prescription/Start screen between Home and the active workout.
struct WorkoutPlayerView: View {
    let workout: PlannedWorkout
    let onFinish: (WorkoutExecutionResult) -> Void
    let onCancel: () -> Void

    @State private var engine: WorkoutExecutionEngine
    @StateObject private var locationTracker: WorkoutLocationTracker
    @State private var lastPulse: Date?
    @State private var showingEndConfirmation = false
    @State private var showingExitConfirmation = false
    @State private var liveActivity = WorkoutLiveActivityController()

    private let pulse = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    @MainActor
    init(
        workout: PlannedWorkout,
        onFinish: @escaping (WorkoutExecutionResult) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.workout = workout
        self.onFinish = onFinish
        self.onCancel = onCancel
        _engine = State(initialValue: WorkoutExecutionEngine(plan: WorkoutExecutionPlan(workout: workout)))
        _locationTracker = StateObject(
            wrappedValue: WorkoutLocationTracker(sport: workout.discipline.sport ?? .running)
        )
    }

    private var recordsGPS: Bool {
        workout.discipline == .running || workout.discipline == .cycling
    }

    var body: some View {
        NavigationStack {
            Group {
                switch engine.phase {
                case .ready:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .running, .paused:
                    activeView
                case .finished:
                    finishedView
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .navigationTitle(workout.discipline.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(engine.phase == .running || engine.phase == .paused)
            .onAppear { startWorkoutIfNeeded() }
            .onReceive(pulse, perform: handlePulse)
            .sensoryFeedback(.success, trigger: engine.currentIndex)
            .alert("End workout?", isPresented: $showingEndConfirmation) {
                Button("End Workout", role: .destructive) { finishWorkout() }
                Button("Keep Going", role: .cancel) {}
            } message: {
                Text("Your active time and recorded GPS up to this point will be saved.")
            }
            .alert("Leave workout?", isPresented: $showingExitConfirmation) {
                Button("Leave", role: .destructive, action: cancelWorkout)
                Button("Keep Workout", role: .cancel) {}
            } message: {
                Text("This workout is still in progress and will not be saved.")
            }
        }
    }

    private var activeView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            if let step = engine.currentStep {
                VStack(spacing: 10) {
                    Text("STEP \(engine.currentIndex + 1) OF \(engine.plan.steps.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)

                    if let repetition = step.repetitionLabel {
                        Text(repetition)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(workout.discipline.tint)
                    }

                    Text(step.title)
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(primaryClock)
                        .font(.system(size: 62, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)

                    Text(clockCaption(for: step))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if recordsGPS {
                        liveGPSMetrics
                            .padding(.top, 8)
                    }

                    if let instructions = step.instructions, !instructions.isEmpty {
                        Text(instructions)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }

                Spacer(minLength: 32)

                if let next = engine.nextStep {
                    HStack {
                        Text("Next")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(next.title)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .padding(14)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 14))
                    .padding(.bottom, 18)
                }

                HStack(spacing: 12) {
                    Button { togglePause() } label: {
                        Label(
                            engine.phase == .paused ? "Resume" : "Pause",
                            systemImage: engine.phase == .paused ? "play.fill" : "pause.fill"
                        )
                    }
                    .buttonStyle(SecondaryActionButtonStyle())

                    Button { completeCurrentStep() } label: {
                        Label(step.usesCountdown ? "Skip" : "Complete Step", systemImage: "forward.fill")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var liveGPSMetrics: some View {
        switch locationTracker.permission {
        case .denied, .restricted:
            Label("GPS unavailable — workout timing continues", systemImage: "location.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unavailable:
            Label("Location services unavailable", systemImage: "location.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            HStack(spacing: 28) {
                metric(
                    TrainingFormatter.distance(meters: locationTracker.snapshot.distanceMeters),
                    label: "Distance"
                )
                if let value = livePaceOrSpeed {
                    metric(value, label: workout.discipline == .cycling ? "Avg speed" : "Avg pace")
                }
            }
        }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var finishedView: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("Workout complete")
                    .font(.title.weight(.semibold))
                Text(TrainingFormatter.totalDuration(seconds: engine.elapsedSeconds))
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                Text("Active time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if recordsGPS, locationTracker.snapshot.distanceMeters > 0 {
                HStack(spacing: 32) {
                    metric(
                        TrainingFormatter.distance(meters: locationTracker.snapshot.distanceMeters),
                        label: "Distance"
                    )
                    if let value = livePaceOrSpeed {
                        metric(value, label: workout.discipline == .cycling ? "Avg speed" : "Avg pace")
                    }
                }
            }

            Spacer()

            Button("Save & Add Report") { saveWorkout() }
                .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if engine.phase == .running || engine.phase == .paused {
                Button("Close") { showingExitConfirmation = true }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            if engine.phase == .running || engine.phase == .paused {
                Button("End") { showingEndConfirmation = true }
                    .foregroundStyle(.red)
            }
        }
    }

    private var primaryClock: String {
        if let remaining = engine.remainingSeconds { return clock(remaining) }
        return clock(engine.stepElapsedSeconds)
    }

    private var livePaceOrSpeed: String? {
        let distance = locationTracker.snapshot.distanceMeters
        guard distance >= 20, engine.elapsedSeconds > 0 else { return nil }
        let metersPerSecond = distance / engine.elapsedSeconds
        guard metersPerSecond > 0 else { return nil }

        if workout.discipline == .cycling {
            return String(format: "%.1f km/h", metersPerSecond * 3.6)
        }

        let secondsPerKm = Int((1_000 / metersPerSecond).rounded())
        guard secondsPerKm > 0, secondsPerKm < 3_600 else { return nil }
        return String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60)
    }

    private func clockCaption(for step: ExecutableWorkoutStep) -> String {
        if let distance = step.distanceMeters, !step.usesCountdown {
            return "Stopwatch · \(TrainingFormatter.distance(meters: distance)) target"
        }
        return step.usesCountdown ? "remaining" : "elapsed"
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remaining = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remaining) }
        return String(format: "%02d:%02d", minutes, remaining)
    }

    private func startWorkoutIfNeeded() {
        guard engine.phase == .ready else { return }
        let now = Date.now
        engine.start(now: now)
        if recordsGPS { locationTracker.start() }
        lastPulse = now

        if engine.phase == .running, let state = activityState(now: now) {
            liveActivity.start(
                workoutTitle: workout.title,
                disciplineName: workout.discipline.displayName,
                state: state
            )
        } else if engine.phase == .finished {
            locationTracker.stop()
        }
    }

    private func togglePause() {
        if engine.phase == .paused {
            engine.resume()
            if recordsGPS { locationTracker.resume() }
            lastPulse = .now
        } else {
            engine.pause()
            if recordsGPS { locationTracker.pause() }
            lastPulse = nil
        }
        syncLiveActivity()
    }

    private func completeCurrentStep() {
        engine.completeCurrentStep(now: .now)
        if engine.phase == .finished {
            locationTracker.stop()
            liveActivity.end(finalState: nil)
        } else {
            syncLiveActivity()
        }
        lastPulse = engine.phase == .running ? .now : nil
    }

    private func finishWorkout() {
        engine.finish(now: .now)
        locationTracker.stop()
        liveActivity.end(finalState: nil)
        lastPulse = nil
    }

    private func cancelWorkout() {
        locationTracker.discard()
        liveActivity.end(finalState: nil)
        onCancel()
    }

    private func saveWorkout() {
        guard let base = engine.result else { return }
        liveActivity.end(finalState: nil)
        let gps = locationTracker.snapshot
        let result = WorkoutExecutionResult(
            workoutID: base.workoutID,
            startedAt: base.startedAt,
            endedAt: base.endedAt,
            elapsedSeconds: base.elapsedSeconds,
            distanceMeters: gps.distanceMeters > 0 ? gps.distanceMeters : nil,
            route: gps.route
        )
        onFinish(result)
    }

    private func handlePulse(_ now: Date) {
        guard engine.phase == .running else {
            lastPulse = nil
            return
        }

        let previous = lastPulse ?? now
        let previousIndex = engine.currentIndex
        engine.advance(by: now.timeIntervalSince(previous), now: now)

        if engine.phase == .finished {
            locationTracker.stop()
            liveActivity.end(finalState: nil)
        } else if engine.currentIndex != previousIndex {
            syncLiveActivity(now: now)
        }
        lastPulse = engine.phase == .running ? now : nil
    }

    private func syncLiveActivity(now: Date = .now) {
        guard let state = activityState(now: now) else { return }
        liveActivity.update(state)
    }

    private func activityState(now: Date) -> WorkoutActivityAttributes.ContentState? {
        guard let step = engine.currentStep else { return nil }
        let paused = engine.phase == .paused
        let isCountdown = step.usesCountdown
        let displayedSeconds = engine.remainingSeconds ?? engine.stepElapsedSeconds

        return WorkoutActivityAttributes.ContentState(
            stepTitle: step.title,
            stepPosition: "Step \(engine.currentIndex + 1) of \(engine.plan.steps.count)",
            repetition: step.repetitionLabel,
            isPaused: paused,
            isCountdown: isCountdown,
            timerStartedAt: !paused && !isCountdown ? now.addingTimeInterval(-engine.stepElapsedSeconds) : nil,
            timerEndsAt: !paused && isCountdown ? now.addingTimeInterval(engine.remainingSeconds ?? 0) : nil,
            frozenSeconds: displayedSeconds
        )
    }
}