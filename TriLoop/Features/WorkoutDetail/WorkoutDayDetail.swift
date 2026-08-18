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
    @State private var isConfirmingShift = false
    @State private var samples: WorkoutSamples?
    @State private var samplesFailure: String?
    @State private var isImporting = false
    @State private var importMessage: String?
    @AppStorage("simulateHealthSamples") private var simulateSamples = false

    private let health = HealthKitWorkoutImporter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                // A finished session leads with what happened; an upcoming one
                // leads with what to do.
                if let summary = workout.importedSummary {
                    RecordedWorkoutView(workout: workout, summary: summary)
                }

                if let samples, !samples.isEmpty {
                    WorkoutChartsView(discipline: workout.discipline, samples: samples)
                } else if workout.importedSummary != nil, let samplesFailure {
                    Text(samplesFailure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if workout.importedSummary == nil, workout.hasReport {
                    unlinkedSession
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
                        Text("Purpose")
                            .font(.subheadline.weight(.semibold))
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
                        SectionEyebrow(text: "Target effort")
                        Text("RPE \(TrainingFormatter.rpe(rpe))")
                            .font(.body.weight(.medium))
                        EffortBar(range: rpe)
                    }
                }

                if canShift {
                    Button("Missed this? Move the week on a day") {
                        isConfirmingShift = true
                    }
                    .font(.subheadline)
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
            "Move the rest of the week forward by one day?",
            isPresented: $isConfirmingShift,
            titleVisibility: .visible
        ) {
            Button("Move the week on") { shiftWeek() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Today becomes recovery and every remaining session moves on a day. Anything past Sunday is dropped.")
        }
        .sheet(isPresented: $isPresentingFeedback) {
            FeedbackSheet(workout: workout)
        }
    }

    /// Only offered for a training session that has not been reported on and is
    /// not in the future: shifting a day that has not arrived makes no sense.
    private var canShift: Bool {
        guard workout.discipline.isTrainingSession, !workout.hasReport else { return false }
        return Calendar.current.startOfDay(for: workout.date) <= Calendar.current.startOfDay(for: .now)
    }

    private func shiftWeek() {
        guard let plan = workout.plan else { return }
        let outcome = PlanStore(context: modelContext).shiftWeekForward(plan, from: workout.date)

        scheduleMessage = outcome.dropped.map {
            "Week moved on. \($0.displayName) dropped off the end."
        } ?? "Week moved on by a day."
    }

    /// Pinned to the bottom so the primary action is reachable without scrolling
    /// past the whole prescription.
    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 8) {
            if let scheduleMessage {
                Text(scheduleMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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

    /// A session reported by hand has no sensor data behind it. Import only ever
    /// ran for the current week from Settings, so an older week could sit here
    /// forever with nothing explaining the empty space.
    @ViewBuilder
    private var unlinkedSession: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Recorded data")

            Text("No Apple Health workout is linked to this session, so there is no heart rate or pace detail.")
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
        // Ahead of the summary check: simulated series are built from the
        // prescription, so they work on sessions Health never recorded.
        #if DEBUG
        if simulateSamples, workout.isCompleted {
            samples = SimulatedWorkoutSamples.make(for: workout)
            samplesFailure = nil
            return
        }
        #endif

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
                scheduleMessage = "Scheduled for \(when.formatted(date: .abbreviated, time: .shortened)). Open the Workout app on your Watch to start it."
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
                }
            }
        }
    }
}

