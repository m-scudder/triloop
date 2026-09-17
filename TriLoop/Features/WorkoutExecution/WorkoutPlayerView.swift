import Combine
import SwiftUI

/// Executes the exact prescription already stored on the workout.
///
/// Duration steps are countdown timers. Distance-only/manual steps are
/// stopwatches and wait for the athlete to confirm completion. The engine uses
/// wall-clock deltas, so returning from the background catches a running timer
/// up instead of silently losing elapsed time.
struct WorkoutPlayerView: View {
    let workout: PlannedWorkout
    let onFinish: (WorkoutExecutionResult) -> Void
    let onCancel: () -> Void

    @State private var engine: WorkoutExecutionEngine
    @State private var lastPulse: Date?
    @State private var showingEndConfirmation = false
    @State private var showingExitConfirmation = false

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
    }

    var body: some View {
        NavigationStack {
            Group {
                switch engine.phase {
                case .ready:
                    readyView
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
            .onReceive(pulse, perform: handlePulse)
            .sensoryFeedback(.success, trigger: engine.currentIndex)
            .alert("End workout?", isPresented: $showingEndConfirmation) {
                Button("End Workout", role: .destructive) {
                    engine.finish(now: .now)
                    lastPulse = nil
                }
                Button("Keep Going", role: .cancel) {}
            } message: {
                Text("Your active time up to this point will be saved.")
            }
            .alert("Leave workout?", isPresented: $showingExitConfirmation) {
                Button("Leave", role: .destructive, action: onCancel)
                Button("Keep Workout", role: .cancel) {}
            } message: {
                Text("This workout is still in progress and will not be saved.")
            }
        }
    }

    private var readyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(workout.title)
                        .font(.largeTitle.weight(.semibold))

                    if let summary = WorkoutStructureSummary.text(for: workout) {
                        Text(summary)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    if !workout.goal.isEmpty {
                        Text(workout.goal)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionEyebrow(text: "Workout")

                    ForEach(Array(engine.plan.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(.fill.tertiary, in: .circle)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.subheadline.weight(.medium))
                                Text(stepPrescription(step))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                Button("Start Workout") {
                    let now = Date.now
                    engine.start(now: now)
                    lastPulse = now
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
            .padding(.top, 12)
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
                    Button {
                        togglePause()
                    } label: {
                        Label(
                            engine.phase == .paused ? "Resume" : "Pause",
                            systemImage: engine.phase == .paused ? "play.fill" : "pause.fill"
                        )
                    }
                    .buttonStyle(SecondaryActionButtonStyle())

                    Button {
                        engine.completeCurrentStep(now: .now)
                        lastPulse = engine.phase == .running ? .now : nil
                    } label: {
                        Label(step.usesCountdown ? "Skip" : "Complete Step", systemImage: "forward.fill")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
            }
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

            Spacer()

            Button("Save & Add Report") {
                guard let result = engine.result else { return }
                onFinish(result)
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if engine.phase == .running || engine.phase == .paused {
                Button("Close") { showingExitConfirmation = true }
            } else if engine.phase != .finished {
                Button("Close", action: onCancel)
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
        if let remaining = engine.remainingSeconds {
            return clock(remaining)
        }
        return clock(engine.stepElapsedSeconds)
    }

    private func clockCaption(for step: ExecutableWorkoutStep) -> String {
        if let distance = step.distanceMeters, !step.usesCountdown {
            return "Stopwatch · \(TrainingFormatter.distance(meters: distance)) target"
        }
        return step.usesCountdown ? "remaining" : "elapsed"
    }

    private func stepPrescription(_ step: ExecutableWorkoutStep) -> String {
        var parts: [String] = []
        if let repetition = step.repetitionLabel { parts.append(repetition) }
        if let duration = step.durationSeconds {
            parts.append(TrainingFormatter.totalDuration(seconds: duration))
        }
        if let distance = step.distanceMeters {
            parts.append(TrainingFormatter.distance(meters: distance))
        }
        return parts.isEmpty ? "Manual step" : parts.joined(separator: " · ")
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%02d:%02d", minutes, remaining)
    }

    private func togglePause() {
        if engine.phase == .paused {
            engine.resume()
            lastPulse = .now
        } else {
            engine.pause()
            lastPulse = nil
        }
    }

    private func handlePulse(_ now: Date) {
        guard engine.phase == .running else {
            lastPulse = nil
            return
        }

        let previous = lastPulse ?? now
        engine.advance(by: now.timeIntervalSince(previous), now: now)
        lastPulse = engine.phase == .running ? now : nil
    }
}
