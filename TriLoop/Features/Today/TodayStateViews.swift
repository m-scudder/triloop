import SwiftUI

/// The upcoming-workout state (§4): the default training day.
///
/// Everything here answers "what am I doing, and how hard". Analysis belongs in
/// Workout Detail, and the athlete should not have to read past anything to
/// find the action.
struct TodayWorkoutView: View {
    let workout: PlannedWorkout
    let isScheduledOnWatch: Bool
    let isScheduling: Bool
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(workout.discipline.displayName.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                Text(workout.title)
                    .font(.largeTitle.weight(.semibold))

                HStack(spacing: 12) {
                    if let seconds = workout.prescribedDurationSeconds ?? workout.estimatedDurationSeconds {
                        Text(TrainingFormatter.totalDuration(seconds: seconds))
                            .font(.title3.weight(.medium))
                    }
                    if let effort = TodayEffort.text(for: workout.targetRPE) {
                        Text(effort)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let structure = WorkoutStructureSummary.text(for: workout) {
                Text(structure)
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 12))
            }

            if let cue = TodayCoachingCue.text(for: workout) {
                Text(cue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button(isScheduling ? "Sending…" : "Send to Apple Watch", action: start)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(isScheduling)

                NavigationLink("View workout") {
                    WorkoutDayDetail(workout: workout)
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }

            if isScheduledOnWatch {
                Label("Ready on Apple Watch", systemImage: "checkmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The gap between finishing on the Watch and Health delivering the workout.
///
/// TriLoop cannot see a session while it runs — a workout reaches HealthKit
/// only once it ends — so this claims the one thing WorkoutKit does report:
/// the scheduled workout is marked complete. No elapsed time is shown, because
/// none is known.
struct TodayAwaitingImportView: View {
    let workout: PlannedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                "\(workout.discipline.displayName.uppercased()) FINISHED",
                systemImage: "checkmark.circle"
            )
            .font(.headline)
            .foregroundStyle(.green)

            Text(workout.title)
                .font(.title2.weight(.semibold))

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for Health to sync the details")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("TriLoop will ask how it felt as soon as they arrive.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// The completed-and-reviewed state (§14): closure, then what's next.
struct TodayCompletedView: View {
    let workout: PlannedWorkout
    let outcome: ExecutionComparison.Outcome?
    let explanation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("\(workout.discipline.displayName.uppercased()) COMPLETE", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            if let summary = workout.importedSummary {
                TodayMetricsRow(summary: summary, sport: workout.discipline.sport)
            }

            if let rpe = workout.feedback?.rpe {
                Text("RPE \(rpe)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let outcome {
                Text(outcome.overall.displayName)
                    .font(.title3.weight(.semibold))
            }

            if let explanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            NavigationLink("View analysis") {
                WorkoutDayDetail(workout: workout)
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
    }
}

/// The few metrics worth seeing immediately (§12).
///
/// Absent values are omitted rather than shown as zero, so a swim without a
/// heart-rate strap simply reads shorter.
struct TodayMetricsRow: View {
    let summary: ImportedWorkoutSummary
    let sport: Sport?

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            StatTile(value: TrainingFormatter.totalDuration(seconds: summary.duration), label: "Time")

            if let distance = summary.distanceMeters, distance > 0 {
                StatTile(value: TrainingFormatter.distance(meters: distance), label: "Distance")
            }

            if let pace = paceText {
                StatTile(value: pace, label: sport == .swimming ? "Per 100m" : "Pace")
            }

            if let heartRate = summary.averageHeartRate {
                StatTile(value: "\(Int(heartRate.rounded()))", label: "Avg bpm")
            }

            Spacer(minLength: 0)
        }
    }

    private var paceText: String? {
        guard let distance = summary.distanceMeters, distance > 0, summary.duration > 0 else { return nil }

        if sport == .swimming {
            return TrainingFormatter.swimPace(secondsPer100m: summary.duration / (distance / 100))
        }
        let secondsPerKm = Int((summary.duration / (distance / 1_000)).rounded())
        return String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
    }
}

/// Rest, recovery, missed, skipped and week-complete (§17–20).
///
/// One shape for all of them: a heading, a neutral explanation, and at most one
/// action. Nothing here uses guilt or fills the day with analytics.
struct TodayStatementView: View {
    let heading: String
    let message: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(heading.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            Text(message)
                .font(.title3.weight(.medium))

            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryActionButtonStyle())
            }
        }
    }
}

/// Lightweight future context (§10), as one line rather than a section of its
/// own. The week itself belongs to Plan.
struct TodayNextView: View {
    let next: NextSession
    /// Rest days have nothing above this line, so the label earns its place.
    var isLabelled = false

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var text: String {
        var parts = [relativeDay, next.discipline.displayName]
        if let seconds = next.durationSeconds {
            parts.append(TrainingFormatter.totalDuration(seconds: seconds))
        }
        let line = parts.joined(separator: " · ")
        return isLabelled ? "Next: \(line)" : line
    }

    private var relativeDay: String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(next.date) { return "Tomorrow" }
        return next.date.formatted(.dateTime.weekday(.wide))
    }
}

/// How the week is going, without becoming a second Plan or Progress.
///
/// Deliberately small: it is context for today's session, not the subject of
/// the screen.
struct TodayGlanceView: View {
    let tiles: [GlanceTile]

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "At a glance")

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(tiles) { tile in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tile.value)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text(tile.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
