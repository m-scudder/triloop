import Combine
import SwiftUI

/// Executes the exact prescription already stored on the workout.
/// Opening this screen prepares audio when enabled, then starts execution.
struct WorkoutPlayerView: View {
    let workout: PlannedWorkout
    let onFinish: (WorkoutExecutionResult) -> Void
    let onCancel: () -> Void

    @State private var engine: WorkoutExecutionEngine
    @StateObject private var locationTracker: WorkoutLocationTracker
    @StateObject private var coach = WorkoutAudioCoach()
    @AppStorage(AudioCoachingPreferences.enabledKey) private var coachingEnabled = true
    @AppStorage(AudioCoachingPreferences.countdownsKey) private var coachingCountdowns = true
    @AppStorage(AudioCoachingPreferences.volumeKey) private var coachingVolume = 0.8
    @State private var preparationComplete = false
    @State private var preparationMessage: String?
    @State private var audioSetupMessage: String?
    @State private var showingAudioControls = false
    @State private var hasLeft = false
    @State private var didSave = false
    @State private var lastPulse: Date?
    @State private var showingEndConfirmation = false
    @State private var showingExitConfirmation = false
    @State private var liveActivity = WorkoutLiveActivityController()
    @State private var inactiveAt: Date?
    @Environment(\.scenePhase) private var scenePhase

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
                    preparationView
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
        // Keep lifecycle work on the stable container, not the phase-specific
        // Group: changing from preparation to playback must not cancel audio.
        .task { await prepareWorkout() }
        .onDisappear {
            hasLeft = true
            coach.stop()
        }
        .sheet(isPresented: $showingAudioControls) { audioControls }
        .onChange(of: coachingVolume) { _, volume in coach.setVolume(Float(volume)) }
        .onChange(of: scenePhase) { _, newPhase in handleScenePhaseChange(newPhase) }
        .onReceive(pulse, perform: handlePulse)
    }

    private var preparationView: some View {
        VStack(spacing: 20) {
            if let preparationMessage {
                Text(preparationMessage).multilineTextAlignment(.center)
                Button("Start with On-screen Timer") {
                    self.preparationMessage = nil
                    preparationComplete = true
                    startWorkoutIfNeeded()
                }
                .buttonStyle(PrimaryActionButtonStyle())
            } else {
                ProgressView("Preparing workout…")
                Text("Preparing spoken cues before the workout starts.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Cancel", action: cancelWorkout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var audioControls: some View {
        NavigationStack {
            Form {
                Section("Coach volume") {
                    Slider(value: $coachingVolume, in: 0.1...1)
                        .accessibilityLabel("Coach volume")
                    Text("Your phone's media volume also controls what you hear.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Continue without Audio Coaching") {
                    coach.stop()
                    inactiveAt = nil
                    lastPulse = engine.phase == .running ? .now : nil
                    showingAudioControls = false
                    if engine.phase == .finished { completeTrackedWorkout() }
                }
            }
            .navigationTitle("Audio coaching")
            .toolbar { Button("Done") { showingAudioControls = false } }
        }
        .presentationDetents([.medium])
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

                if let message = coach.message ?? audioSetupMessage {
                    Text(message)
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.bottom, 12)
                }

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
                if coach.isPrepared {
                    Button { showingAudioControls = true } label: {
                        Image(systemName: "speaker.wave.2")
                    }
                    .accessibilityLabel("Audio coaching controls")
                }
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

    private func prepareWorkout() async {
        guard engine.phase == .ready, !preparationComplete, !hasLeft else { return }

        // Starting the workout must never wait on speech rendering. Move to the
        // timer immediately, then attach the finite audio programme in the
        // background at the current active-time position when it is ready.
        preparationComplete = true
        startWorkoutIfNeeded()

        guard coachingEnabled, recordsGPS, !hasLeft else { return }

        guard WorkoutCoachingTimeline(
            plan: engine.plan,
            countdowns: coachingCountdowns
        ) != nil else {
            audioSetupMessage = "Audio coaching is unavailable for this workout. The on-screen timer will continue normally."
            return
        }

        do {
            try await coach.prepare(
                plan: engine.plan,
                countdowns: coachingCountdowns,
                volume: Float(coachingVolume)
            )
            try Task.checkCancellation()

            guard !hasLeft,
                  engine.phase == .running || engine.phase == .paused else {
                coach.stop()
                return
            }

            coach.onPause = { pauseWorkout() }
            coach.onFinished = {
                // The workout engine owns completion. Audio ending is never
                // allowed to advance, finish, or save the workout.
                audioSetupMessage = nil
            }

            let joinPosition = min(
                engine.elapsedSeconds,
                coach.timeline?.duration ?? engine.elapsedSeconds
            )
            coach.seek(to: joinPosition)

            if engine.phase == .running, !coach.play() {
                coach.stop()
                audioSetupMessage = "Audio coaching could not start. The workout timer will continue without spoken cues."
            }
        } catch is CancellationError {
            coach.stop()
        } catch {
            guard !hasLeft, !Task.isCancelled else { return }
            coach.stop()
            audioSetupMessage = "Spoken guidance could not be prepared. The workout timer will continue without audio."
        }
    }

    private func startWorkoutIfNeeded() {
        guard engine.phase == .ready, preparationComplete, scenePhase == .active, !hasLeft else { return }
        let now = Date.now
        engine.start(now: now)
        if recordsGPS { locationTracker.start() }
        lastPulse = now
        if coach.isPrepared, !coach.play() {
            coach.stop()
            audioSetupMessage = "Audio coaching could not start. The workout timer will continue without spoken cues."
        }

        if let state = activityState(now: now) {
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
        if engine.phase == .paused { resumeWorkout() }
        else { pauseWorkout() }
    }

    private func pauseWorkout() {
        guard engine.phase == .running else { return }
        if coach.isPrepared {
            coach.pause()
        }
        engine.pause()
        if recordsGPS { locationTracker.pause() }
        lastPulse = nil
        inactiveAt = nil
        syncLiveActivity()
    }

    private func resumeWorkout() {
        guard engine.phase == .paused else { return }
        if coach.isPrepared, !coach.play() {
            coach.stop()
            audioSetupMessage = "Audio coaching could not resume. The workout timer will continue without spoken cues."
        }
        engine.resume()
        if recordsGPS { locationTracker.resume() }
        lastPulse = .now
        inactiveAt = nil
        syncLiveActivity()
    }

    private func completeCurrentStep() {
        guard engine.phase == .running || engine.phase == .paused else { return }
        guard engine.phase != .finished else { return }
        let wasPaused = engine.phase == .paused
        engine.completeCurrentStep(now: .now)

        if engine.phase == .finished {
            coach.stop()
            locationTracker.stop()
            liveActivity.end(finalState: nil)
        } else {
            if coach.isPrepared {
                coach.seekToStep(engine.currentIndex)
                if wasPaused, !coach.play() { engine.pause() }
            }
            if wasPaused, engine.phase == .running, recordsGPS {
                locationTracker.resume()
            }
            syncLiveActivity()
        }
        lastPulse = engine.phase == .running ? .now : nil
    }

    private func finishWorkout() {
        coach.stop()
        engine.finish(now: .now)
        locationTracker.stop()
        liveActivity.end(finalState: nil)
        lastPulse = nil
    }

    private func cancelWorkout() {
        hasLeft = true
        coach.stop()
        locationTracker.discard()
        liveActivity.end(finalState: nil)
        onCancel()
    }

    private func saveWorkout() {
        guard !didSave, let base = engine.result else { return }
        didSave = true
        hasLeft = true
        coach.stop()
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
        guard scenePhase == .active,
              engine.phase == .running else {
            lastPulse = nil
            return
        }

        let previous = lastPulse ?? now
        let previousIndex = engine.currentIndex
        engine.advance(by: max(now.timeIntervalSince(previous), 0), now: now)

        if engine.phase == .finished {
            completeTrackedWorkout()
            return
        }

        if engine.currentIndex != previousIndex {
            syncLiveActivity(now: now)
        }
        lastPulse = now
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active, engine.phase == .ready {
            startWorkoutIfNeeded()
            return
        }
        switch phase {
        case .inactive, .background:
            if engine.phase == .running, inactiveAt == nil {
                inactiveAt = .now
            }
            lastPulse = nil

        case .active:
            reconcileAfterBackground()

        @unknown default:
            break
        }
    }

    private func reconcileAfterBackground(now: Date = .now) {
        guard let inactiveAt else {
            lastPulse = engine.phase == .running ? now : nil
            return
        }
        self.inactiveAt = nil

        guard engine.phase == .running else {
            lastPulse = nil
            return
        }

        let previousIndex = engine.currentIndex

        // A user-started timed workout continues while the phone is locked.
        // Catch up across timed steps using the real inactive duration. Manual
        // or distance steps remain manual and can never be completed by this.
        engine.advance(
            by: max(now.timeIntervalSince(inactiveAt), 0),
            now: now
        )

        if engine.phase == .finished {
            completeTrackedWorkout()
            return
        }

        if engine.currentIndex != previousIndex {
            syncLiveActivity(now: now)
        }
        lastPulse = now
    }

    private func completeTrackedWorkout() {
        guard engine.phase == .finished else { return }
        locationTracker.stop()
        liveActivity.end(finalState: nil)
        lastPulse = nil
        saveWorkout()
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
