import SwiftUI

struct WatchWorkoutPlayerView: View {
    let workout: WatchWorkoutPayload

    @EnvironmentObject private var manager: WatchWorkoutSessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showsEndConfirmation = false

    var body: some View {
        Group {
            if manager.state == .finished {
                finishedView
            } else {
                activeView
            }
        }
        .navigationBarBackButtonHidden(manager.isActive)
        .confirmationDialog(
            "End workout?",
            isPresented: $showsEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Workout", role: .destructive) {
                manager.end()
            }
            Button("Keep Going", role: .cancel) {}
        }
    }

    private var activeView: some View {
        ScrollView {
            VStack(spacing: 12) {
                stepCard
                metrics
                controls
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(workout.discipline.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var stepCard: some View {
        if let step = manager.currentStep {
            VStack(alignment: .leading, spacing: 8) {
                if let round = step.repetitionLabel {
                    Text(round.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(step.title)
                    .font(.title3.weight(.bold))

                if let intensity = step.targetIntensity {
                    Text(intensity.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(primaryProgressText)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()

                if let progress = manager.engine?.stepProgress {
                    ProgressView(value: progress)
                }

                if let instructions = step.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let next = manager.nextStep {
                    Divider()
                    Text("Next: \(next.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if step.durationSeconds == nil && step.distanceMeters == nil {
                    Button("Next Step") {
                        manager.completeCurrentStep()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ProgressView()
        }
    }

    private var metrics: some View {
        VStack(spacing: 7) {
            HStack {
                metric(
                    value: manager.heartRate.map { "\(Int($0.rounded()))" } ?? "—",
                    label: "BPM"
                )
                metric(
                    value: distanceText,
                    label: "Distance"
                )
            }

            HStack {
                metric(
                    value: elapsedText,
                    label: "Time"
                )
                metric(
                    value: "\(Int(manager.activeEnergyKilocalories.rounded()))",
                    label: "kcal"
                )
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                if manager.state == .paused {
                    manager.resume()
                } else {
                    manager.pause()
                }
            } label: {
                Image(systemName: manager.state == .paused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                showsEndConfirmation = true
            } label: {
                Image(systemName: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var finishedView: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: manager.savedWorkoutUUID == nil
                      ? "exclamationmark.circle"
                      : "checkmark.circle.fill")
                    .font(.largeTitle)

                Text("Workout Finished")
                    .font(.headline)

                HStack {
                    metric(value: elapsedText, label: "Time")
                    metric(value: distanceText, label: "Distance")
                }

                Text(manager.savedWorkoutUUID == nil
                     ? "The session ended. Check the message below if HealthKit could not save it."
                     : "Saved to Apple Health. Athevia on iPhone will match it to this planned workout automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let error = manager.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("Done") {
                    manager.reset()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var primaryProgressText: String {
        if let remaining = manager.engine?.remainingSeconds {
            return remaining.watchClockText
        }
        if let remaining = manager.engine?.remainingDistanceMeters {
            return remaining.atheviaWatchDistanceText
        }
        return manager.engine?.stepElapsedSeconds.watchClockText ?? "0:00"
    }

    private var distanceText: String {
        manager.distanceMeters > 0
            ? manager.distanceMeters.atheviaWatchDistanceText
            : "—"
    }

    private var elapsedText: String {
        manager.elapsedSeconds.watchClockText
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension TimeInterval {
    var watchClockText: String {
        let total = max(Int(self.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
