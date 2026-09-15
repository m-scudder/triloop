import SwiftData
import SwiftUI

struct WorkoutDayDetail: View {
    let workout: PlannedWorkout
    var scheduler: any WorkoutScheduling = WorkoutKitScheduler()

    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingFeedback = false
    @State private var isScheduling = false
    @State private var isScheduled = false
    @State private var scheduleMessage: String?
    @State private var isMoving = false
    @State private var moveDate = Date.now
    @State private var moveFailure: String?
    @State private var isConfirmingSkip = false
    @State private var isChoosingTodayAction = false
    @State private var isConfirmingUnavailable = false
    @State private var samples: WorkoutSamples?
    @State private var samplesFailure: String?
    @State private var isImporting = false
    @State private var importMessage: String?
    @AppStorage("automaticallyImportWorkouts") private var automaticallyImport = true
    @Environment(\.healthProvider) private var health
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var profiles: [AthleteProfile]
    @Query private var recordedSummaries: [ImportedWorkoutSummary]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                // A finished session leads with what happened; an upcoming one
                // leads with what to do.
                if let summary = workout.importedSummary {
                    RecordedWorkoutView(workout: workout, summary: summary)
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

                // §49's order: what happened, how it compared, the heart-rate
                // detail, then the derived readings, then sensor specifics.
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
                    unlinkedSession
                }

                // Effort alone is enough to read intensity and load, so these
                // sit outside the samples branch: a session reported by hand
                // still has something to say about how hard it was.
                intensity(with: zoneBreakdown)

                if let metrics = workout.importedSummary?.metrics {
                    AdvancedMetricsView(metrics: metrics, sport: workout.discipline.sport)
                }

                if workout.isSkipped {
                    stateBanner(
                        "Skipped",
                        detail: "This session was deliberately skipped. It still counts against progression.",
                        symbol: "slash.circle.fill",
                        tint: .secondary
                    ) {
                        EmptyView()
                    }
                } else if workout.isMissed() {
                    stateBanner(
                        "Missed",
                        detail: "This day has passed with nothing recorded. Report it if you trained.",
                        symbol: "exclamationmark.circle.fill",
                        tint: .orange
                    ) {
                        EmptyView()
                    }
                }

                if let feedback = workout.feedback {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(text: "Your report")
                        FeedbackSummaryView(feedback: feedback)
                        Button("Clear report", role: .destructive) {
                            workout.clearCompletion()
                        }
                        .font(.subheadline)
                    }
                }

                if !workout.goal.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(workout.goal)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if workout.orderedSteps.isEmpty {
                    Text("No session today. Rest is part of the plan.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    WorkoutPrescriptionView(workout: workout)
                }

                if let rpe = workout.targetRPE {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SectionEyebrow(text: "Target effort")
                            Spacer()
                            InfoButton(concept: .rpe)
                        }
                        Text("RPE \(TrainingFormatter.rpe(rpe))")
                            .font(.body.weight(.medium))
                        EffortBar(range: rpe)
                    }
                }

                if canSkip {
                    VStack(alignment: .leading, spacing: 16) {
                        Button { presentMove() } label: {
                            Label("Move Workout", systemImage: "calendar")
                        }
                        Button(role: .destructive) { isConfirmingSkip = true } label: {
                            Label("Skip Workout", systemImage: "forward.end")
                        }
                        if Calendar.current.isDateInToday(workout.date) {
                            Button { isChoosingTodayAction = true } label: {
                                Label("Can't Train Today", systemImage: "calendar.badge.exclamationmark")
                            }
                        }
                    }
                    .font(.subheadline)
                }

                if canChangeAvailability, let weekday {
                    Button { isConfirmingUnavailable = true } label: {
                        Label("Mark \(weekday.displayName) Unavailable (Every Week)", systemImage: "calendar.badge.minus")
                    }
                    .font(.subheadline)
                }
                if let scheduleMessage {
                    Text(scheduleMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            if workout.acceptsFeedback || workout.discipline.isTrainingSession {
                actionBar
            }
        }


        .task {
            await refreshScheduledState()
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
        .confirmationDialog("Can't Train Today", isPresented: $isChoosingTodayAction, titleVisibility: .visible) {
            Button("Move This Workout") { presentMove() }
            Button("Skip This Workout Today", role: .destructive) { isConfirmingSkip = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Today only. Your recurring availability will not change.")
        }
        .confirmationDialog("Mark \(weekday?.displayName ?? "Day") unavailable every week?",
                            isPresented: $isConfirmingUnavailable, titleVisibility: .visible) {
            Button("Mark Unavailable Every Week", role: .destructive) { markUnavailable() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes your recurring training schedule. Remaining sessions will be reshaped; those that cannot fit will stay in the plan as skipped. Completed and past sessions stay unchanged.")
        }
        .sheet(isPresented: $isMoving) { moveSheet }
        .sheet(isPresented: $isPresentingFeedback) {
            FeedbackSheet(workout: workout)
        }
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
                        DatePicker("Move to", selection: $moveDate,
                                   in: max(plan.startDate, Calendar.current.startOfDay(for: .now))...plan.endDate,
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    }
                    if let moveFailure { Text(moveFailure).foregroundStyle(.red) }
                    Button("Move Workout") {
                        do {
                            try PlanStore(context: modelContext).moveWorkout(workout, to: moveDate)
                            scheduleMessage = "Workout moved to \(workout.date.formatted(date: .abbreviated, time: .omitted))."
                            isMoving = false
                            Task { await WatchScheduleSync.sync(plan) }
                        } catch { moveFailure = error.localizedDescription }
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

    @ViewBuilder
    private func stateBanner(
        _ title: String,
        detail: String,
        symbol: String,
        tint: Color,
        @ViewBuilder action: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            action()
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 14))
    }

    private func skipWorkout() {
        do {
            try PlanStore(context: modelContext).skipWorkout(workout)
            scheduleMessage = "Workout skipped. Recurring availability is unchanged."
            if let plan = workout.plan { Task { await WatchScheduleSync.sync(plan) } }
        } catch { scheduleMessage = error.localizedDescription }
    }

    private func markUnavailable() {
        guard let weekday else { return }
        do {
            let skipped = try PlanStore(context: modelContext).markDayUnavailable(weekday)
            scheduleMessage = "\(weekday.displayName) is now unavailable every week. \(skipped) workouts could not fit and were kept as skipped."
            if let plan = workout.plan { Task { await WatchScheduleSync.sync(plan) } }
        } catch { scheduleMessage = error.localizedDescription }
    }

    /// Pinned to the bottom so the primary action is reachable without scrolling
    /// past the whole prescription.
    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if workout.acceptsFeedback {
                    Button {
                        isPresentingFeedback = true
                    } label: {
                        Text(workout.hasReport ? "Update Report" : "Mark as Done")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }

                if workout.discipline.isTrainingSession {
                    Button {
                        sendToWatch()
                    } label: {
                        Label(
                            isScheduled ? "On Watch" : "Send to Watch",
                            systemImage: isScheduled ? "checkmark.circle.fill" : "applewatch"
                        )
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(isScheduled ? Color.green : .primary)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(isScheduling || isScheduled)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// The hardest effort the athlete has actually recorded, which can raise a
    /// ceiling the age formula underestimates.
    private var observedMaximumHeartRate: Double? {
        recordedSummaries.compactMap(\.maximumHeartRate).max()
    }

    private var builder: TrainingIntelligenceBuilder {
        TrainingIntelligenceBuilder(
            birthDate: profiles.first?.setup?.birthDate,
            observedMaximumHeartRate: observedMaximumHeartRate
        )
    }

    /// §3: one interpretation, shared with Progress and the history browser.
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

    /// Nil when there is no heart rate to derive zones from, which is normal
    /// for a manually reported session.
    private var zoneBreakdown: HeartRateZoneBreakdown? {
        interpretation?.zones
    }

    /// A missing ceiling is worth saying out loud, since the athlete can fix it.
    /// Missing heart rate is not: the charts above already show there is none.
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

    /// Only shown when something was actually measured. §33: silence is more
    /// honest than labelling an unmeasured session easy.
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

    /// A session reported by hand has no sensor data behind it. Import only ever
    /// ran for the current week from Settings, so an older week could sit here
    /// forever with nothing explaining the empty space.
    private var unlinkedSession: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Recorded data")

            Text("No linked Apple Health workout. Heart rate and pace unavailable.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let importMessage {
                Text(importMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(isImporting ? "Looking…" : "Look in Apple Health") {
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

    /// Fetched rather than stored: HealthKit already holds every sample, and a
    /// copy would be a lot of data for a screen opened occasionally.
    private func loadSamples() async {
        guard let id = workout.importedSummary?.healthKitUUID else { return }

        guard await health.authorizationStatus == .authorized else {
            samplesFailure = "Connect Apple Health to see heart rate and pace detail."
            return
        }

        do {
            let loaded = try await health.samples(forWorkout: id)
            samples = loaded
            samplesFailure = loaded.isEmpty
                ? "Apple Health has no heart rate or pace samples for this session."
                : nil
        } catch {
            samplesFailure = "Could not read the detail for this session."
        }
    }

    private func refreshScheduledState() async {
        isScheduled = await scheduler.scheduledWorkoutIDs().contains(workout.id)
    }

    private func sendToWatch() {
        isScheduling = true
        let when = workout.suggestedScheduleDate()

        Task {
            defer { isScheduling = false }
            do {
                try await scheduler.schedule(workout, at: when)
                isScheduled = true
                // The scheduled hour is an artefact of WorkoutKit needing a
                // wall-clock time; TriLoop prescribes the day, so it is not
                // shown to the athlete as though it were a commitment.
                scheduleMessage = "Ready in the Workout app on your Watch. Start it whenever you train today."
            } catch WorkoutSchedulingError.notAuthorized {
                scheduleMessage = "TriLoop needs permission to add workouts to your Watch."
            } catch WorkoutSchedulingError.unavailable {
                scheduleMessage = "No paired Apple Watch found."
            } catch WorkoutSchedulingError.notAccepted {
                scheduleMessage = "The Watch did not accept the workout. Check that it is paired and nearby."
            } catch {
                scheduleMessage = "This session cannot be sent to the Watch."
            }
        }
    }

    @ViewBuilder
    private var completionSection: some View {
        if let feedback = workout.feedback {
            LabeledSection(title: "Your report") {
                VStack(alignment: .leading, spacing: 12) {
                    FeedbackSummaryView(feedback: feedback)

                    Button("Clear report", role: .destructive) {
                        workout.clearCompletion()
                    }
                    .font(.subheadline)
                }
            }
        } else {
            Button {
                isPresentingFeedback = true
            } label: {
                Label("Mark complete", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: workout.discipline.symbolName)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .background(.fill.tertiary, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    if let summary = WorkoutSummaryText.make(for: workout) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let provenance = WorkoutEvidencePresentation.provenance(workout.origin) {
                        Text(provenance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

