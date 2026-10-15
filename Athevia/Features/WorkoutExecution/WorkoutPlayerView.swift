import Combine
import SwiftUI

/// Executes the exact prescription already stored on the workout.
/// Opening this screen prepares audio when enabled, then starts execution.
struct WorkoutPlayerView: View {
    @Environment(\.atheviaTheme) private var theme

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
    @State private var immediateCountdownStepID: String?
    @State private var segmentStartDistance: Double = 0
    @State private var stepStartDistance: Double = 0
    @State private var segmentStartElapsed: TimeInterval = 0
    @State private var activeSegmentKey: String?
    @State private var completedMultisportSegments: [RecordedMultisportSegment] = []
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
        let firstSegmentSport = workout.orderedSteps.compactMap { $0.kind.segmentSport }.first
        _locationTracker = StateObject(
            wrappedValue: WorkoutLocationTracker(
                sport: workout.discipline.sport ?? firstSegmentSport ?? .running
            )
        )
    }

    private var recordsGPS: Bool {
        workout.discipline == .running
            || workout.discipline == .cycling
            || workout.discipline == .multisport
    }

    private var activeMetricSport: Sport? {
        if workout.discipline == .multisport {
            return engine.currentStep?.kind.segmentSport
        }
        return workout.discipline.sport
    }

    private var activeSegmentDistance: Double {
        max(locationTracker.snapshot.distanceMeters - segmentStartDistance, 0)
    }

    private var activeSegmentElapsed: TimeInterval {
        max(engine.elapsedSeconds - segmentStartElapsed, 0)
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
            .atheviaScreen()
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
        .atheviaScreen()
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
                    .font(.footnote).foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            }
            Button("Cancel", action: cancelWorkout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var audioControls: some View {
        NavigationStack {
            Form {
                Group {
                Section("Coach volume") {
                    Slider(value: $coachingVolume, in: 0.1...1)
                        .accessibilityLabel("Coach volume")
                    Text("Your phone's media volume also controls what you hear.")
                        .font(.footnote).foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }
                Button("Continue without Audio Coaching") {
                    coach.stop()
                    inactiveAt = nil
                    lastPulse = engine.phase == .running ? .now : nil
                    showingAudioControls = false
                    if engine.phase == .finished { completeTrackedWorkout() }
                }
                }
                .atheviaListRow()
            }
            .atheviaList()
            .atheviaScreen()
            .navigationTitle("Audio coaching")
            .toolbar { Button("Done") { showingAudioControls = false } }
        }
        .atheviaScreen()
        .presentationDetents([.medium])
    }

    private var activeView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            if let step = engine.currentStep {
                VStack(spacing: 10) {
                    Text("STEP \(engine.currentIndex + 1) OF \(engine.plan.steps.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        .tracking(0.8)

                    if let repetition = step.repetitionLabel {
                        Text(repetition)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(workout.discipline.themedTint(theme))
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
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))

                    if recordsGPS, activeMetricSport == .running || activeMetricSport == .cycling {
                        liveGPSMetrics
                            .padding(.top, 8)
                    }

                    if let instructions = step.instructions, !instructions.isEmpty {
                        Text(instructions)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                            .padding(.top, 6)
                    }
                }

                Spacer(minLength: 32)

                if let message = coach.message ?? audioSetupMessage {
                    Text(message)
                        .font(.footnote).foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        .multilineTextAlignment(.center).padding(.bottom, 12)
                }

                if let next = engine.nextStep {
                    HStack {
                        Text("Next")
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        Spacer()
                        Text(next.title)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .padding(14)
                    .background(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface), in: .rect(cornerRadius: 14))
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
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        case .unavailable:
            Label("Location services unavailable", systemImage: "location.slash")
                .font(.caption)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        default:
            VStack(spacing: 8) {
                HStack(spacing: 28) {
                    metric(
                        TrainingFormatter.distance(meters: activeSegmentDistance),
                        label: "Distance"
                    )
                    if let value = livePaceOrSpeed {
                        metric(value, label: activeMetricSport == .cycling ? "Avg speed" : "Avg pace")
                    }
                }

                Label("GPS continues with the screen locked or app in background", systemImage: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
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
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        }
    }

    private var finishedView: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(AtheviaAdaptiveStyle(.green, gaming: .success))

            VStack(spacing: 6) {
                Text("Workout complete")
                    .font(.title.weight(.semibold))
                Text(TrainingFormatter.totalDuration(seconds: engine.elapsedSeconds))
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                Text("Active time")
                    .font(.caption)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
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
                    .foregroundStyle(AtheviaAdaptiveStyle(.red, gaming: .danger))
            }
        }
    }

    private var primaryClock: String {
        if let remainingDistance = engine.remainingDistanceMeters {
            return TrainingFormatter.distance(meters: remainingDistance)
        }
        if let remaining = engine.remainingSeconds { return clock(remaining) }
        return clock(engine.stepElapsedSeconds)
    }

    private var livePaceOrSpeed: String? {
        let distance = activeSegmentDistance
        let elapsed = activeSegmentElapsed
        guard distance >= 20, elapsed > 0 else { return nil }
        let metersPerSecond = distance / elapsed
        guard metersPerSecond > 0 else { return nil }

        if activeMetricSport == .cycling {
            return String(format: "%.1f km/h", metersPerSecond * 3.6)
        }

        let secondsPerKm = Int((1_000 / metersPerSecond).rounded())
        guard secondsPerKm > 0, secondsPerKm < 3_600 else { return nil }
        return String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60)
    }

    private func clockCaption(for step: ExecutableWorkoutStep) -> String {
        if step.distanceMeters != nil, !step.usesCountdown {
            return "distance remaining"
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

        // The workout timer starts immediately. Live TTS announces the current
        // step right away while the finite lock-screen-safe programme renders
        // in the background.
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

        if let currentStep = engine.currentStep {
            coach.announceImmediately(
                step: currentStep,
                volume: Float(coachingVolume)
            )
        }

        do {
            try await coach.waitForImmediateCueToStart()
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

            // If a live cue is still speaking, let it finish rather than
            // overlapping it with the pre-rendered programme.
            try await coach.waitForImmediateCueToFinish()
            try Task.checkCancellation()

            guard !hasLeft,
                  engine.phase == .running || engine.phase == .paused else {
                coach.stop()
                return
            }

            let rawJoinPosition = min(
                engine.elapsedSeconds,
                coach.timeline?.duration ?? engine.elapsedSeconds
            )
            let joinPosition = coach.safeJoinPosition(rawJoinPosition)
            coach.seek(to: joinPosition)

            if engine.phase == .running, !coach.play() {
                audioSetupMessage = "Audio coaching could not start. Live spoken cues will continue when possible."
            }
        } catch is CancellationError {
            coach.stop()
        } catch {
            guard !hasLeft, !Task.isCancelled else { return }
            audioSetupMessage = "Pre-rendered coaching could not be prepared. Live spoken cues will continue when possible."
        }
    }

    private func startWorkoutIfNeeded() {
        guard engine.phase == .ready, preparationComplete, scenePhase == .active, !hasLeft else { return }
        ProductAnalytics.shared.track(.action(.startWorkout, .requested))
        let now = Date.now
        engine.start(now: now)
        ProductAnalytics.shared.track(.action(.startWorkout, engine.phase == .running ? .succeeded : .failed))
        if recordsGPS {
            syncMultisportSegmentBoundary(force: true)
            locationTracker.start()
            stepStartDistance = locationTracker.snapshot.distanceMeters
        }
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
        if coachingEnabled {
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
            audioSetupMessage = "Pre-rendered coaching could not resume. Live spoken cues will continue when possible."
        }
        engine.resume()

        if coachingEnabled,
           !coach.isPlaying,
           let currentStep = engine.currentStep {
            coach.announceImmediately(
                step: currentStep,
                volume: Float(coachingVolume)
            )
        }
        if recordsGPS { locationTracker.resume() }
        lastPulse = .now
        inactiveAt = nil
        syncLiveActivity()
    }

    private func completeCurrentStep() {
        guard engine.phase == .running || engine.phase == .paused else { return }
        guard engine.phase != .finished else { return }
        let wasPaused = engine.phase == .paused
        let previousSegmentKey = currentSegmentKey
        engine.completeCurrentStep(now: .now)
        stepStartDistance = locationTracker.snapshot.distanceMeters
        if currentSegmentKey != previousSegmentKey {
            syncMultisportSegmentBoundary()
        }

        if engine.phase == .finished {
            coach.stop()
            locationTracker.stop()
            liveActivity.end(finalState: nil)
        } else {
            immediateCountdownStepID = nil

            if coach.isPrepared {
                coach.seekToStep(engine.currentIndex)
                if wasPaused, !coach.play() { engine.pause() }
            }

            if coachingEnabled,
               !coach.isPlaying,
               let currentStep = engine.currentStep {
                coach.announceImmediately(
                    step: currentStep,
                    volume: Float(coachingVolume)
                )
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
            route: gps.route,
            multisportSegments: finalizedMultisportSegments()
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

        if engine.phase != .finished,
           engine.currentIndex == previousIndex,
           engine.currentStep?.distanceMeters != nil,
           engine.currentStep?.durationSeconds == nil {
            let stepDistance = max(
                locationTracker.snapshot.distanceMeters - stepStartDistance,
                0
            )
            engine.updateCurrentStepDistance(stepDistance, now: now)
        }

        if engine.phase == .finished {
            completeTrackedWorkout()
            return
        }

        if engine.currentIndex != previousIndex {
            stepStartDistance = locationTracker.snapshot.distanceMeters
            syncMultisportSegmentBoundary()
            immediateCountdownStepID = nil

            if coachingEnabled,
               !coach.isPlaying,
               let currentStep = engine.currentStep {
                coach.announceImmediately(
                    step: currentStep,
                    volume: Float(coachingVolume)
                )
            }

            syncLiveActivity(now: now)
        } else {
            announceImmediateCountdownIfNeeded()
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

        // Timed work catches up from wall-clock time. Distance work uses the
        // GPS distance accumulated since that step began.
        engine.advance(
            by: max(now.timeIntervalSince(inactiveAt), 0),
            now: now
        )

        if engine.phase != .finished,
           engine.currentIndex == previousIndex,
           engine.currentStep?.distanceMeters != nil,
           engine.currentStep?.durationSeconds == nil {
            let stepDistance = max(
                locationTracker.snapshot.distanceMeters - stepStartDistance,
                0
            )
            engine.updateCurrentStepDistance(stepDistance, now: now)
        }

        if engine.phase == .finished {
            completeTrackedWorkout()
            return
        }

        if engine.currentIndex != previousIndex {
            stepStartDistance = locationTracker.snapshot.distanceMeters
            syncMultisportSegmentBoundary()
            immediateCountdownStepID = nil

            if coachingEnabled,
               !coach.isPlaying,
               let currentStep = engine.currentStep {
                coach.announceImmediately(
                    step: currentStep,
                    volume: Float(coachingVolume)
                )
            }

            syncLiveActivity(now: now)
        } else {
            announceImmediateCountdownIfNeeded()
        }
        lastPulse = now
    }

    private func announceImmediateCountdownIfNeeded() {
        guard coachingEnabled,
              coachingCountdowns,
              !coach.isPlaying,
              let step = engine.currentStep,
              let duration = step.durationSeconds,
              duration >= 30,
              let remaining = engine.remainingSeconds,
              remaining > 0,
              remaining <= 10,
              immediateCountdownStepID != step.id else {
            return
        }

        immediateCountdownStepID = step.id
        coach.announceImmediateCountdown(
            nextStep: engine.nextStep,
            volume: Float(coachingVolume)
        )
    }

    private func completeTrackedWorkout() {
        guard engine.phase == .finished else { return }
        locationTracker.stop()
        liveActivity.end(finalState: nil)
        lastPulse = nil
        saveWorkout()
    }

    private var currentSegmentKey: String? {
        guard workout.discipline == .multisport, let kind = engine.currentStep?.kind else { return nil }
        if kind.isTransition { return "transition" }
        return kind.segmentSport?.rawValue
    }

    private func syncMultisportSegmentBoundary(force: Bool = false) {
        guard workout.discipline == .multisport else { return }
        let nextKey = currentSegmentKey
        if !force, nextKey == activeSegmentKey { return }

        if let previous = activeSegmentKey {
            appendCompletedSegment(key: previous)
        }

        activeSegmentKey = nextKey
        segmentStartDistance = locationTracker.snapshot.distanceMeters
        segmentStartElapsed = engine.elapsedSeconds

        if let sport = activeMetricSport, sport == .running || sport == .cycling {
            locationTracker.setSport(sport)
        }
    }

    private func appendCompletedSegment(key: String) {
        let duration = max(engine.elapsedSeconds - segmentStartElapsed, 0)
        let distance = max(locationTracker.snapshot.distanceMeters - segmentStartDistance, 0)
        if key == "transition" {
            completedMultisportSegments.append(
                RecordedMultisportSegment(
                    sport: nil,
                    isTransition: true,
                    durationSeconds: duration
                )
            )
            return
        }
        guard let sport = Sport(rawValue: key) else { return }
        completedMultisportSegments.append(
            RecordedMultisportSegment(
                sport: sport,
                durationSeconds: duration,
                distanceMeters: distance > 0 ? distance : nil
            )
        )
    }

    private func finalizedMultisportSegments() -> [RecordedMultisportSegment] {
        guard workout.discipline == .multisport else { return [] }
        var result = completedMultisportSegments
        guard let key = activeSegmentKey else { return result }

        let duration = max(engine.elapsedSeconds - segmentStartElapsed, 0)
        let distance = max(locationTracker.snapshot.distanceMeters - segmentStartDistance, 0)
        if key == "transition" {
            result.append(.init(sport: nil, isTransition: true, durationSeconds: duration))
        } else if let sport = Sport(rawValue: key) {
            result.append(.init(
                sport: sport,
                durationSeconds: duration,
                distanceMeters: distance > 0 ? distance : nil
            ))
        }
        return result
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
