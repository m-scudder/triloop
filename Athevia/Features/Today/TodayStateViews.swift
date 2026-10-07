import SwiftData
import SwiftUI
import UIKit

/// The upcoming-workout state (§4): the default training day.
///
/// Home owns workout execution. Plan and Workout Detail explain the plan and
/// result without repeating these primary actions.
struct TodayWorkoutView: View {
    @Environment(\.atheviaTheme) private var theme

    let workout: PlannedWorkout
    let isScheduledOnWatch: Bool
    let isScheduling: Bool
    let markDone: () -> Void
    /// Existing Watch scheduling action. In-app execution is owned locally so
    /// it works regardless of Watch availability.
    let start: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [AthleteProfile]
    @StateObject private var locationPermission = WorkoutLocationPermissionRequester()
    @StateObject private var watch = WatchAvailability.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsPlayer = false
    @State private var showsLocationIssue = false
    @State private var pendingResult: WorkoutExecutionResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label(workout.discipline.displayName, systemImage: workout.discipline.symbolName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(workout.discipline.themedTint(theme))

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(workout.title)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(2)

                    if let target = WorkoutSummaryText.make(for: workout) {
                        Text("· \(target)")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                            .lineLimit(1)
                    }
                }
            }

            if let structure = WorkoutStructureSummary.text(for: workout) {
                Text(structure)
                    .font(.body.weight(.medium))
            }

            if let cue = TodayCoachingCue.text(for: workout) {
                Text(cue)
                    .font(.subheadline)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            }

            if workout.discipline == .running
                || workout.discipline == .cycling
                || workout.discipline == .multisport {
                NavigationLink {
                    AudioCoachingSettingsView()
                } label: {
                    Label("Audio coaching", systemImage: "speaker.wave.2")
                        .font(.subheadline.weight(.medium))
                }
            }

            HStack(spacing: 10) {
                Button("Start Workout", action: beginPhoneWorkout)
                    .buttonStyle(PrimaryActionButtonStyle())

                if watch.canSchedule && !isScheduledOnWatch {
                    Button(action: start) {
                        Label(
                            isScheduling ? "Sending…" : "Send to Watch",
                            systemImage: "applewatch"
                        )
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(isScheduling)
                }
            }

            NavigationLink {
                WorkoutDayDetail(workout: workout)
            } label: {
                HStack {
                    Text("Workout details")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.vertical, 4)
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { watch.refresh() }
        }
        .fullScreenCover(
            isPresented: $showsPlayer,
            onDismiss: {
                savePendingResult()
                PhoneWorkoutExecutionState.end(workout.id)
            }
        ) {
            WorkoutPlayerView(
                workout: workout,
                onFinish: { result in
                    pendingResult = result
                    showsPlayer = false
                },
                onCancel: { showsPlayer = false }
            )
        }
        .alert("GPS access is off", isPresented: $showsLocationIssue) {
            Button("Continue Without GPS") {
                PhoneWorkoutExecutionState.begin(workout.id)
                showsPlayer = true
            }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                PhoneWorkoutExecutionState.end(workout.id)
            }
        } message: {
            Text("Athevia needs location access to record distance, pace and route for this workout. You can still run the workout timer without GPS.")
        }
    }

    /// Ask before presenting the player. Requesting from inside a newly
    /// presented full-screen cover can race the cover animation and leave the
    /// system permission sheet unseen. Swimming never requests GPS.
    private func beginPhoneWorkout() {
        guard workout.discipline == .running
                || workout.discipline == .cycling
                || workout.discipline == .multisport else {
            PhoneWorkoutExecutionState.begin(workout.id)
            showsPlayer = true
            return
        }

        locationPermission.request { result in
            switch result {
            case .allowed:
                PhoneWorkoutExecutionState.begin(workout.id)
                showsPlayer = true
            case .denied, .unavailable:
                showsLocationIssue = true
            }
        }
    }

    private func resolveEventCompletionIfNeeded(_ summary: ImportedWorkoutSummary) {
        guard let profile = profiles.first,
              var setup = profile.setup,
              setup.eventState.status == .upcoming,
              let event = setup.objective.event,
              EventCompletionEvidenceMatcher().matches(event: event, summary: summary) else {
            return
        }

        setup.eventState = AthleteEventState(
            status: .completed,
            resolvedAt: summary.endDate,
            completionEvidence: .atheviaWorkout
        )
        profile.setup = setup
        try? modelContext.save()
    }


    /// Store phone execution in the same normalized summary used by HealthKit
    /// imports. That lets the existing analysis pipeline consume duration,
    /// distance and speed regardless of whether a Watch was present.
    private func savePendingResult() {
        guard let result = pendingResult,
              result.workoutID == workout.id else { return }
        pendingResult = nil

        let isMultisport = workout.discipline == .multisport
        let carrierSport = workout.discipline.sport
            ?? result.multisportSegments.compactMap(\.sport).first
        guard let carrierSport else { return }

        let averageSpeed: Double? = {
            guard !isMultisport,
                  let distance = result.distanceMeters,
                  distance > 0,
                  result.elapsedSeconds > 0 else { return nil }
            return distance / result.elapsedSeconds
        }()

        let metrics = RecordedMetrics(
            averageRunningSpeed: carrierSport == .running ? averageSpeed : nil,
            averageCyclingSpeed: carrierSport == .cycling ? averageSpeed : nil,
            multisportSegments: result.multisportSegments,
            route: result.route
        )

        let summary = ImportedWorkoutSummary(
            healthKitUUID: UUID(),
            sport: carrierSport,
            startDate: result.startedAt,
            endDate: result.endedAt,
            duration: result.elapsedSeconds,
            distanceMeters: isMultisport ? nil : result.distanceMeters,
            metrics: metrics.isEmpty ? nil : metrics,
            source: "Athevia iPhone"
        )
        modelContext.insert(summary)
        workout.attach(summary)
        resolveEventCompletionIfNeeded(summary)
        markDone()
    }
}

/// The gap between finishing on the Watch and Health delivering the workout.
struct TodayAwaitingImportView: View {
    let workout: PlannedWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("\(workout.discipline.displayName.uppercased()) FINISHED", systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(AtheviaAdaptiveStyle(.green, gaming: .success))

            Text(workout.title)
                .font(.title2.weight(.semibold))

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for Apple Health to sync workout details")
                    .font(.subheadline)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            }
        }
    }
}

struct TodayCompletedView: View {
    let workout: PlannedWorkout
    let outcome: ExecutionComparison.Outcome?
    let explanation: String?

    @State private var isSharingWorkout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("\(workout.discipline.displayName.uppercased()) COMPLETE", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AtheviaAdaptiveStyle(.green, gaming: .success))

                Spacer()

                Button {
                    isSharingWorkout = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share workout")
                .accessibilityHint("Creates a shareable summary of this completed workout.")
            }

            if let summary = workout.importedSummary {
                TodayMetricsRow(summary: summary, sport: workout.discipline.sport)
            }

            if let outcome {
                Text(outcome.overall.displayName)
                    .font(.title3.weight(.semibold))
            }

            if let explanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            }

            NavigationLink("View analysis") {
                WorkoutDayDetail(workout: workout)
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
        .sheet(isPresented: $isSharingWorkout) {
            WorkoutShareView(workout: workout)
        }
    }
}

struct TodayMetricsRow: View {
    let summary: ImportedWorkoutSummary
    let sport: Sport?

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            StatTile(value: TrainingFormatter.totalDuration(seconds: summary.duration), label: "Time")

            if let distance = summary.distanceMeters, distance > 0 {
                StatTile(value: TrainingFormatter.distance(meters: distance), label: "Distance")
            }

            if let secondaryMetric {
                StatTile(value: secondaryMetric.value, label: secondaryMetric.label)
            }

            Spacer(minLength: 0)
        }
    }

    private var secondaryMetric: (value: String, label: String)? {
        guard let distance = summary.distanceMeters,
              distance > 0,
              summary.duration > 0 else {
            return nil
        }

        switch sport {
        case .swimming:
            return (
                TrainingFormatter.swimPace(
                    secondsPer100m: summary.duration / (distance / 100)
                ),
                "Per 100m"
            )

        case .cycling:
            let kilometresPerHour = distance / summary.duration * 3.6
            return (String(format: "%.1f", kilometresPerHour), "Avg speed · km/h")

        case .running:
            let secondsPerKm = Int((summary.duration / (distance / 1_000)).rounded())
            return (
                String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60),
                "Pace · /km"
            )

        case nil:
            return nil
        }
    }
}

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
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                .tracking(0.8)

            Text(message)
                .font(.title3.weight(.medium))

            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryActionButtonStyle())
            }
        }
    }
}

struct TodayNextView: View {
    let next: NextSession
    var isLabelled = false

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
    }

    private var text: String {
        var parts = [relativeDay, next.discipline.displayName]
        if let distance = next.distanceMeters {
            parts.append(TrainingFormatter.distance(meters: distance))
        } else if let seconds = next.durationSeconds {
            parts.append(TrainingFormatter.totalDuration(seconds: seconds))
        }
        let line = parts.joined(separator: " · ")
        return isLabelled ? "Next: \(line)" : line
    }

    private var relativeDay: String {
        let calendar = Calendar.current
        if calendar.isDateInTomorrow(next.date) { return "Tomorrow" }
        return TrainingFormatter.weekdayAbbreviation(for: next.date)
    }
}

struct TodayGlanceView: View {
    let tiles: [GlanceTile]
    var showsHeader = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                SectionEyebrow(text: "At a glance")
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(tiles) { tile in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tile.value)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Text(tile.label)
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                            if tile.slot == .adherence {
                                InfoButton(concept: .adherence)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }
}

