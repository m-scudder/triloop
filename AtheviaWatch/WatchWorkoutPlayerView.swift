import SwiftUI

struct WatchWorkoutPlayerView: View {
    let workout: WatchWorkoutPayload

    @EnvironmentObject private var manager: WatchWorkoutSessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var page = 1
    @State private var crownPage = 1.0
    @State private var showsEndConfirmation = false

    var body: some View {
        Group {
            if manager.state == .finished {
                finishedView
            } else {
                activeWorkoutView
            }
        }
        .background(Color.black)
        .navigationBarBackButtonHidden(manager.isActive)
        .confirmationDialog(
            "End Workout?",
            isPresented: $showsEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Workout", role: .destructive) {
                manager.end()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var activeWorkoutView: some View {
        TabView(selection: $page) {
            workoutControls
                .tag(0)

            workoutMetrics
                .tag(1)

            upNextView
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .focusable()
        .digitalCrownRotation(
            $crownPage,
            from: 0,
            through: 2,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownPage) { _, value in
            let newPage = min(max(Int(value.rounded()), 0), 2)
            if newPage != page {
                page = newPage
            }
        }
        .onChange(of: page) { _, value in
            let doubleValue = Double(value)
            if crownPage != doubleValue {
                crownPage = doubleValue
            }
        }
    }

    // MARK: - Apple Workout style controls page

    private var workoutControls: some View {
        VStack(spacing: 12) {
            workoutHeader

            Spacer(minLength: 0)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                controlButton(
                    title: "End",
                    systemImage: "xmark",
                    tint: .red
                ) {
                    showsEndConfirmation = true
                }

                controlButton(
                    title: manager.state == .paused ? "Resume" : "Pause",
                    systemImage: manager.state == .paused ? "play.fill" : "pause.fill",
                    tint: .yellow
                ) {
                    if manager.state == .paused {
                        manager.resume()
                    } else {
                        manager.pause()
                    }
                }

                controlButton(
                    title: "Metrics",
                    systemImage: "chart.bar.fill",
                    tint: .green
                ) {
                    page = 1
                }

                controlButton(
                    title: "Next",
                    systemImage: "forward.end.fill",
                    tint: .blue,
                    disabled: manager.currentStep == nil
                ) {
                    manager.completeCurrentStep()
                    page = 2
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    private func controlButton(
        title: String,
        systemImage: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.22))
                        .frame(width: 52, height: 52)

                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint)
                }

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    // MARK: - Apple Workout style metrics page

    private var workoutMetrics: some View {
        VStack(alignment: .leading, spacing: 0) {
            workoutHeader

            Spacer(minLength: 4)

            metricRow(
                label: "Elapsed Time",
                value: elapsedText,
                tint: .yellow
            )

            switch workout.discipline {
            case .running:
                metricRow(
                    label: "Heart Rate",
                    value: heartRateText,
                    tint: .red
                )
                metricRow(
                    label: "Current Pace",
                    value: currentRunPaceText,
                    tint: .green
                )
                metricRow(
                    label: "Average Pace",
                    value: averageRunPaceText,
                    tint: .green
                )
                metricRow(
                    label: "Distance",
                    value: distanceText,
                    tint: .cyan
                )

            case .cycling:
                metricRow(
                    label: "Heart Rate",
                    value: heartRateText,
                    tint: .red
                )
                metricRow(
                    label: "Current Speed",
                    value: currentCycleSpeedText,
                    tint: .green
                )
                metricRow(
                    label: "Average Speed",
                    value: averageCycleSpeedText,
                    tint: .green
                )
                metricRow(
                    label: "Distance",
                    value: distanceText,
                    tint: .cyan
                )

            case .swimming:
                metricRow(
                    label: "Distance",
                    value: swimDistanceText,
                    tint: .cyan
                )
                metricRow(
                    label: "Heart Rate",
                    value: heartRateText,
                    tint: .red
                )
                metricRow(
                    label: "Average Pace",
                    value: averageSwimPaceText,
                    tint: .green
                )
                metricRow(
                    label: "Active Calories",
                    value: caloriesText,
                    tint: .pink
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    private func metricRow(
        label: String,
        value: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
    }

    // MARK: - Apple Custom Workout "Up Next" view

    @ViewBuilder
    private var upNextView: some View {
        if let step = manager.currentStep {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    workoutHeader

                    Text(step.kind.appleWorkoutLabel.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(step.kind.tint)

                    if let repetition = step.repetitionLabel {
                        Text(repetition)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(step.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(primaryProgressText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(step.kind.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let progress = manager.engine?.stepProgress {
                        ProgressView(value: progress)
                            .tint(step.kind.tint)
                    }

                    if let intensity = step.targetIntensity {
                        Text(intensity.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    if let next = manager.nextStep {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("UP NEXT")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(next.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)

                                Spacer(minLength: 4)

                                Text(next.prescriptionText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Text("Final interval")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        } else {
            ProgressView()
        }
    }

    private var workoutHeader: some View {
        HStack(spacing: 5) {
            Image(systemName: workout.discipline.symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)

            Text(workout.discipline.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
                .lineLimit(1)

            Spacer()

            if manager.state == .paused {
                Text("PAUSED")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.yellow)
            }
        }
    }

    // MARK: - Apple-style completion summary

    private var finishedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Workout Ended")
                    .font(.headline)
                    .foregroundStyle(.white)

                summaryRow("Total Time", elapsedText)
                summaryRow("Distance", distanceText)
                summaryRow("Active Calories", caloriesText)

                if let average = manager.averageHeartRate {
                    summaryRow("Avg. Heart Rate", "\(Int(average.rounded())) BPM")
                }

                if let error = manager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if manager.savedWorkoutUUID != nil {
                    Label("Saved to Health", systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button("Done") {
                    manager.reset()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }

    // MARK: - Metric formatting

    private var primaryProgressText: String {
        if let remaining = manager.engine?.remainingSeconds {
            return remaining.watchClockText
        }
        if let remaining = manager.engine?.remainingDistanceMeters {
            return remaining.atheviaWatchDistanceText
        }
        return manager.engine?.stepElapsedSeconds.watchClockText ?? "0:00"
    }

    private var elapsedText: String {
        manager.elapsedSeconds.watchClockText
    }

    private var heartRateText: String {
        guard let heartRate = manager.heartRate else { return "-- BPM" }
        return "\(Int(heartRate.rounded())) BPM"
    }

    private var caloriesText: String {
        "\(Int(manager.activeEnergyKilocalories.rounded())) CAL"
    }

    private var distanceText: String {
        guard manager.distanceMeters > 0 else { return "--" }

        if manager.distanceMeters >= 1000 {
            return String(format: "%.2f KM", manager.distanceMeters / 1000)
        }
        return "\(Int(manager.distanceMeters.rounded())) M"
    }

    private var swimDistanceText: String {
        guard manager.distanceMeters > 0 else { return "-- M" }
        return "\(Int(manager.distanceMeters.rounded())) M"
    }

    private var currentRunPaceText: String {
        guard let speed = manager.currentSpeedMetersPerSecond, speed > 0 else {
            return "--/KM"
        }
        return paceText(secondsPerKilometre: 1000 / speed)
    }

    private var averageRunPaceText: String {
        guard manager.distanceMeters > 0, manager.elapsedSeconds > 0 else {
            return "--/KM"
        }
        return paceText(
            secondsPerKilometre: manager.elapsedSeconds / (manager.distanceMeters / 1000)
        )
    }

    private var currentCycleSpeedText: String {
        guard let speed = manager.currentSpeedMetersPerSecond, speed > 0 else {
            return "-- KM/H"
        }
        return String(format: "%.1f KM/H", speed * 3.6)
    }

    private var averageCycleSpeedText: String {
        guard manager.distanceMeters > 0, manager.elapsedSeconds > 0 else {
            return "-- KM/H"
        }

        let kilometres = manager.distanceMeters / 1000
        let hours = manager.elapsedSeconds / 3600
        return String(format: "%.1f KM/H", kilometres / hours)
    }

    private var averageSwimPaceText: String {
        guard manager.distanceMeters > 0, manager.elapsedSeconds > 0 else {
            return "--/100M"
        }

        let secondsPerHundred = manager.elapsedSeconds / (manager.distanceMeters / 100)
        return paceText(
            secondsPerKilometre: secondsPerHundred,
            suffix: "/100M"
        )
    }

    private func paceText(
        secondsPerKilometre: TimeInterval,
        suffix: String = "/KM"
    ) -> String {
        guard secondsPerKilometre.isFinite, secondsPerKilometre > 0 else {
            return "--\(suffix)"
        }

        let seconds = Int(secondsPerKilometre.rounded())
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d%@", minutes, remainder, suffix)
    }
}

private extension WatchWorkoutStepKind {
    var appleWorkoutLabel: String {
        switch self {
        case .warmUp:
            "Warmup"
        case .work:
            "Work"
        case .recovery:
            "Recovery"
        case .cooldown:
            "Cooldown"
        case .repeatBlock:
            "Repeat"
        }
    }

    var tint: Color {
        switch self {
        case .warmUp, .cooldown:
            .cyan
        case .work:
            .yellow
        case .recovery:
            .green
        case .repeatBlock:
            .orange
        }
    }
}

private extension WatchExecutableWorkoutStep {
    var prescriptionText: String {
        if let durationSeconds {
            return durationSeconds.watchClockText
        }
        if let distanceMeters {
            return distanceMeters.atheviaWatchDistanceText
        }
        return ""
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
