import SwiftData
import SwiftUI

struct WorkoutDayDetail: View {
    let workout: PlannedWorkout
    // Home can still open this view for reference, but plan-management actions
    // belong to the Plan tab and are enabled there explicitly.
    var scheduler: any WorkoutScheduling = WorkoutKitScheduler()
    var showsManagementMenu = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthProvider) private var health
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var profiles: [AthleteProfile]
    @Query private var recordedSummaries: [ImportedWorkoutSummary]

    @State private var isMoving = false
    @State private var moveDate = Date.now
    @State private var moveFailure: String?
    @State private var isConfirmingSkip = false
    @State private var isConfirmingUnavailable = false
    @State private var actionMessage: String?
    @State private var samples: WorkoutSamples?
    @State private var samplesFailure: String?
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var isSharingWorkout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if workout.isSkipped {
                    stateBanner(
                        "Skipped",
                        detail: "This session was deliberately skipped. It still counts against progression.",
                        symbol: "slash.circle.fill",
                        tint: .secondary
                    )
                } else if workout.isMissed() {
                    stateBanner(
                        "Missed",
                        detail: "This day has passed with nothing recorded.",
                        symbol: "exclamationmark.circle.fill",
                        tint: .orange
                    )
                }

                if hasAnalysis {
                    analysisSection

                    if let feedback = workout.feedback {
                        reportSection(feedback)
                    }
                }

                plannedWorkoutSection

                if let actionMessage {
                    Text(actionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .task {
            await loadSamples()
        }
        .confirmationDialog(
            "Skip this workout?",
            isPresented: $isConfirmingSkip,
            titleVisibility: .visible
        ) {
            Button("Skip Workout", role: .destructive) { skipWorkout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only this workout will be skipped. The original session stays in your plan history.")
        }
        .confirmationDialog(
            "Mark \(weekday?.displayName ?? "Day") unavailable every week?",
            isPresented: $isConfirmingUnavailable,
            titleVisibility: .visible
        ) {
            Button("Mark Unavailable Every Week", role: .destructive) { markUnavailable() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes your recurring training schedule. Remaining sessions will be reshaped; those that cannot fit will stay in the plan as skipped. Completed and past sessions stay unchanged.")
        }
        .sheet(isPresented: $isMoving) { moveSheet }
        .sheet(isPresented: $isSharingWorkout) {
            WorkoutShareView(workout: workout)
        }
    }

    private var hasAnalysis: Bool {
        workout.isCompleted
            || execution != nil
            || workout.importedSummary != nil
            || workout.hasReport
    }

    /// Completed sessions lead directly with the evidence that exists. Missing
    /// device evidence removes sensor-only sections rather than leaving holes.
    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                SectionEyebrow(text: "Workout analysis")
                Spacer()
                if let execution {
                    Text(execution.overall.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let execution {
                SessionExecutionView(
                    outcome: execution,
                    plannedSeconds: workout.prescribedDurationSeconds,
                    actualSeconds: workout.importedSummary?.duration,
                    targetRPE: workout.targetRPE,
                    reportedRPE: workout.feedback?.rpe
                )
            }

            if let feedback = workout.feedback,
               let target = workout.targetRPE {
                effortComparison(target: target, feedback: feedback)
            }

            if let samples, !samples.isEmpty {
                WorkoutChartsView(
                    discipline: workout.discipline,
                    samples: samples,
                    summary: workout.importedSummary
                )

                zones(for: samples)
            } else if workout.importedSummary != nil, let samplesFailure {
                Text(samplesFailure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if workout.importedSummary == nil, workout.hasReport {
                manualSessionNotice
            }

            intensity(with: zoneBreakdown)

            if let metrics = workout.importedSummary?.metrics {
                AdvancedMetricsView(metrics: metrics, sport: workout.discipline.sport)
            }
        }
    }

    /// Effort only becomes user-facing after the athlete has submitted a report.
    /// The two numbers stay visible in analysis instead of being hidden inside a
    /// disclosure, so the target-versus-actual comparison is immediately clear.
    private func effortComparison(target: RPERange, feedback: WorkoutFeedback) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionEyebrow(text: "Effort")
                    Spacer()
                    InfoButton(
                        title: "Effort",
                        explanation: "Target effort is calculated from the workout TriLoop planned. Actual effort comes from the report you shared after the workout."
                    )
                }

                HStack(spacing: 24) {
                    StatTile(
                        value: TrainingFormatter.rpe(target),
                        label: "Target"
                    )
                    StatTile(
                        value: "\(feedback.rpe)/10",
                        label: "Actual"
                    )
                }
            }
        }
    }

    private func reportSection(_ feedback: WorkoutFeedback) -> some View {
        DisclosureCard(
            "Your report",
            subtitle: "Effort \(feedback.rpe)/10",
            systemImage: "checkmark.bubble"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                FeedbackSummaryView(feedback: feedback)

                Button("Clear report", role: .destructive) {
                    workout.clearCompletion()
                }
                .font(.subheadline)
            }
        }
    }

    /// Planned sessions expose their prescription directly on Plan. After a
    /// workout is complete, the historical prescription becomes secondary to
    /// analysis and is available as a collapsed reference.
    @ViewBuilder
    private var plannedWorkoutSection: some View {
        if workout.isCompleted {
            DisclosureCard(
                workout.orderedSteps.isEmpty ? "Rest day" : "Planned workout",
                subtitle: WorkoutStructureSummary.text(for: workout) ?? WorkoutSummaryText.make(for: workout),
                systemImage: workout.orderedSteps.isEmpty ? "moon.zzz" : "list.bullet"
            ) {
                prescriptionContent
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                SectionEyebrow(text: workout.orderedSteps.isEmpty ? "Rest day" : "Planned workout")
                prescriptionContent
            }
        }
    }

    @ViewBuilder
    private var prescriptionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let provenance = WorkoutEvidencePresentation.provenance(workout.origin) {
                Text(provenance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !workout.goal.isEmpty {
                Text(workout.goal)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if workout.orderedSteps.isEmpty {
                Text("No session today. Rest is part of the plan.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                WorkoutPrescriptionView(workout: workout)
            }
        }
    }

    /// Only schedule-management actions live here. Mark-as-done and Watch
    /// actions belong exclusively to Home.
    private var managementMenu: some View {
        Menu {
            if canSkip {
                Button { presentMove() } label: {
                    Label("Move Workout", systemImage: "calendar")
                }
                Button(role: .destructive) { isConfirmingSkip = true } label: {
                    Label("Skip Workout", systemImage: "forward.end")
                }
            }

            if canChangeAvailability, let weekday {
                Button { isConfirmingUnavailable = true } label: {
                    Label(
                        "Mark \(weekday.displayName) Unavailable",
                        systemImage: "calendar.badge.minus"
                    )
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .accessibilityLabel("Workout options")
    }

    private var canSkip: Bool {
        guard let plan = workout.plan else { return false }
        return workout.discipline.isTrainingSession && PlanReshaper().canEdit(workout, in: plan)
    }

    private var weekday: Weekday? { Weekday(date: workout.date) }

    private var canChangeAvailability: Bool {
        guard let plan = workout.plan, let weekday, let setup = profiles.first?.setup else { return false }
        return (try? PlanReshaper().validateWeek(plan, on: workout.date)) != nil
            && setup.schedule.isAvailable(on: weekday)
    }

    private func presentMove() {
        moveDate = workout.date
        moveFailure = nil
        isMoving = true
    }

    @ViewBuilder
    private var moveSheet: some View {
        if let plan = workout.plan {
            NavigationStack {
                Form {
                    if max(plan.startDate, Calendar.current.startOfDay(for: .now)) <= plan.endDate {
                        DatePicker(
                            "Move to",
                            selection: $moveDate,
                            in: max(plan.startDate, Calendar.current.startOfDay(for: .now))...plan.endDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }

                    if let moveFailure {
                        Text(moveFailure).foregroundStyle(.red)
                    }

                    Button("Move Workout") {
                        do {
                            try PlanStore(context: modelContext).moveWorkout(workout, to: moveDate)
                            actionMessage = "Workout moved to \(workout.date.formatted(date: .abbreviated, time: .omitted))."
                            isMoving = false
                            Task { await WatchScheduleSync.sync(plan) }
                        } catch {
                            moveFailure = error.localizedDescription
                        }
                    }
                    .disabled(Calendar.current.isDate(moveDate, inSameDayAs: workout.date))
                }
                .navigationTitle("Move Workout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isMoving = false }
                    }
                }
            }
        }
    }

    private func stateBanner(
        _ title: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 14))
    }

    private func skipWorkout() {
        do {
            try PlanStore(context: modelContext).skipWorkout(workout)
            actionMessage = "Workout skipped. Recurring availability is unchanged."
            if let plan = workout.plan { Task { await WatchScheduleSync.sync(plan) } }
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func markUnavailable() {
        guard let weekday else { return }
        do {
            let skipped = try PlanStore(context: modelContext).markDayUnavailable(weekday)
            actionMessage = "\(weekday.displayName) is now unavailable every week. \(skipped) workouts could not fit and were kept as skipped."
            if let plan = workout.plan { Task { await WatchScheduleSync.sync(plan) } }
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private var observedMaximumHeartRate: Double? {
        recordedSummaries.compactMap(\.maximumHeartRate).max()
    }

    private var builder: TrainingIntelligenceBuilder {
        TrainingIntelligenceBuilder(
            birthDate: profiles.first?.setup?.birthDate,
            observedMaximumHeartRate: observedMaximumHeartRate
        )
    }

    private var interpretation: WorkoutInterpretation? {
        let readings = (samples?.heartRate ?? []).map {
            HeartRateReading(date: $0.date, beatsPerMinute: $0.value)
        }
        guard let evidence = builder.evidence(from: workout, samples: readings) else { return nil }

        let ceiling = builder.ceiling
        return WorkoutIntelligence.interpret(
            evidence,
            maximumHeartRate: ceiling?.maximum,
            zoneSource: ceiling?.source ?? .ageBasedMaximum
        )
    }

    private var execution: ExecutionComparison.Outcome? {
        interpretation?.adherence
    }

    private var zoneBreakdown: HeartRateZoneBreakdown? {
        interpretation?.zones
    }

    @ViewBuilder
    private func zones(for samples: WorkoutSamples) -> some View {
        let result = HeartRateZoneResolver.breakdown(
            heartRate: samples.heartRate,
            birthDate: profiles.first?.setup?.birthDate,
            observedMaximum: observedMaximumHeartRate
        )

        switch result {
        case .success(let breakdown):
            HeartRateZoneView(breakdown: breakdown)
        case .failure(.noCeiling):
            Text(HeartRateZoneResolver.Unavailable.noCeiling.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failure(.noHeartRateSamples):
            EmptyView()
        }
    }

    @ViewBuilder
    private func intensity(with breakdown: HeartRateZoneBreakdown?) -> some View {
        if let interpretation {
            let reading = interpretation.intensity.value
            let load = interpretation.load.value

            if reading != nil || load != nil {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                layout {
                    if let reading {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionEyebrow(text: "Intensity")
                            Text(reading.intensity.displayName)
                                .font(.title3.weight(.semibold))
                            Text(WorkoutEvidencePresentation.source(reading.evidence))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            WhyButton(explanation: WorkoutEvidencePresentation.intensity(reading))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let load {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                SectionEyebrow(text: "Load")
                                Spacer()
                                InfoButton(concept: .trainingLoad, evidence: [
                                    .init(label: "Source", value: WorkoutEvidencePresentation.source(load.provenance))
                                ])
                            }
                            Text("\(Int(load.value.rounded()))")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                            Text(WorkoutEvidencePresentation.source(load.provenance))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var manualSessionNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: "Recorded manually")
            Text("Sensor-based charts, heart rate and pace detail aren't available for this workout.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let importMessage {
                Text(importMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(isImporting ? "Looking…" : "Check Apple Health") {
                importThisSession()
            }
            .font(.subheadline)
            .disabled(isImporting)
        }
    }

    private func importThisSession() {
        guard let plan = workout.plan else { return }
        isImporting = true

        Task {
            defer { isImporting = false }
            do {
                let service = WorkoutImportService(context: modelContext, provider: health)
                try await service.importWorkouts(for: plan)
                importMessage = workout.importedSummary == nil
                    ? "Apple Health has no workout matching this session."
                    : nil
                await loadSamples()
            } catch {
                importMessage = "Could not reach Apple Health."
            }
        }
    }

    private func loadSamples() async {
        guard let id = workout.importedSummary?.healthKitUUID else { return }

        guard await health.authorizationStatus == .authorized else {
            samplesFailure = "Connect Apple Health to see sensor-based detail."
            return
        }

        do {
            let loaded = try await health.samples(forWorkout: id)
            samples = loaded
            samplesFailure = loaded.isEmpty
                ? "No sensor-based heart rate or pace samples were recorded for this session."
                : nil
        } catch {
            samplesFailure = "Could not read the sensor-based detail for this session."
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: workout.discipline.symbolName)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 52, height: 52)
                .background(.fill.tertiary, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(workout.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)

                    if workout.status == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Completed")
                    }
                }

                if let summary = WorkoutSummaryText.make(for: workout) {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if workout.isCompleted {
                Button {
                    isSharingWorkout = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Share workout")
                .accessibilityHint("Creates a shareable summary of this completed workout.")
            }

            if showsManagementMenu && (canSkip || canChangeAvailability) {
                managementMenu
            }
        }
    }
}
