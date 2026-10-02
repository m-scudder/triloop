import SwiftData
import SwiftUI

/// Home answers two questions: how is my week going, and what does Athevia want
/// from me right now?
///
/// The weekly overview provides orientation while `TodayPresentationState`
/// still guarantees exactly one primary action for the current day.
struct TodayView: View {
    @Query(sort: \WeeklyPlan.startDate, order: .reverse) private var plans: [WeeklyPlan]
    @Query private var profiles: [AthleteProfile]
    @Query private var summaries: [ImportedWorkoutSummary]

    @AppStorage("automaticallyScheduleWorkouts") private var automaticallySchedule = true
    @State private var isScheduling = false
    @State private var scheduleMessage: String?
    @State private var scheduledWorkoutIDs: Set<UUID> = []
    @State private var finishedOnWatch: Set<UUID> = []
    @State private var feedbackWorkout: PlannedWorkout?
    @State private var sharingWorkout: PlannedWorkout?
    @State private var checkInWorkout: PlannedWorkout?
    @State private var isResolved = false

    @Environment(\.scenePhase) private var scenePhase

    private let scheduler = WorkoutKitScheduler()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let plan = plans.currentPlan() {
                        WeeklyPlanOverviewView(plan: plan)
                    }

                    if let setup = profiles.first?.setup,
                       let event = setup.objective.event,
                       let eventDate = event.eventDate {
                        NavigationLink {
                            FullTrainingJourneyView(
                                setup: setup,
                                plans: plans
                            )
                        } label: {
                            Card {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface))
                                            .frame(width: 42, height: 42)

                                        Image(systemName: "flag.checkered")
                                            .font(.subheadline.weight(.semibold))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Race Plan")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)

                                        Text(event.displayName)
                                            .font(.caption)
                                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 8)

                                    VStack(alignment: .trailing, spacing: 2) {
                                        if let days = event.daysRemaining(), days >= 0 {
                                            Text("\(days) days")
                                                .font(.caption.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(.primary)
                                        }

                                        Text(TrainingFormatter.shortDate(eventDate))
                                            .font(.caption2)
                                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                    }

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AtheviaAdaptiveStyle(.tertiary, gaming: .secondaryText))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if let pending = pendingCheckIn {
                        if checkInLeads {
                            checkInCard(pending)
                        } else {
                            checkInPrompt(pending)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        SectionEyebrow(text: eyebrow)
                        primary
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .atheviaScreen()
            .navigationTitle(TrainingFormatter.shortDate(.now))
            .navigationBarTitleDisplayMode(.inline)
            .analyticsScreen(.home)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { profileButton }
            }
            .overlay(alignment: .bottom) { toast }
            .animation(.default, value: scheduleMessage)
            .sheet(item: $feedbackWorkout) { FeedbackSheet(workout: $0) }
            .sheet(item: $sharingWorkout) { WorkoutShareView(workout: $0) }
            .sheet(item: $checkInWorkout) { RecoveryCheckInSheet(workout: $0) }
            .task(id: scenePhase) { await refresh() }
            .onAppear { Task { await syncWatchState() } }
        }
        .atheviaScreen()
    }

    @ViewBuilder
    private var profileButton: some View {
        if let profile = profiles.first {
            NavigationLink {
                TrainingProfileView(profile: profile)
            } label: {
                Group {
                    if let monogram = monogram(of: profile.name) {
                        Text(monogram)
                            .font(.footnote.weight(.semibold))
                    } else {
                        Image(systemName: "person.fill")
                            .font(.footnote)
                    }
                }
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface), in: .circle)
            }
            .accessibilityLabel("Training profile")
        }
    }

    private func monogram(of name: String) -> String? {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }

    private func checkInPrompt(_ pending: PlannedWorkout) -> some View {
        Button {
            checkInWorkout = pending
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sun.horizon")
                Text("How do you feel after yesterday?")
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(12)
            .background(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func checkInCard(_ pending: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrow(text: "Yesterday")

            Text("How do you feel after \(pending.title)?")
                .font(.title3.weight(.medium))

            Text("Your answer is what decides how hard the coming days are.")
                .font(.subheadline)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))

            Button("Check in") { checkInWorkout = pending }
                .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    @ViewBuilder
    private var primary: some View {
        switch presentation.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)

        case .noPlan:
            TodayStatementView(
                heading: "No plan yet",
                message: "Your first training week has not been generated.",
                detail: "Finish setting up in Settings to get started."
            )

        case .recoveryRequired(let id):
            if let workout = workout(id) {
                recoveryWorkout(workout)
            }

        case .needsFeedback(let id):
            if let workout = workout(id) {
                feedbackNeeded(workout)
            }

        case .upcoming(let id):
            if let workout = workout(id) {
                if workout.discipline == .recovery {
                    recoveryWorkout(workout)
                } else {
                    TodayWorkoutView(
                        workout: workout,
                        isScheduledOnWatch: scheduledWorkoutIDs.contains(workout.id),
                        isScheduling: isScheduling,
                        markDone: { feedbackWorkout = workout },
                        start: { send(workout) }
                    )
                    completedSummaries
                }
            }

        case .awaitingImport(let id):
            if let workout = workout(id) {
                TodayAwaitingImportView(workout: workout)
                completedSummaries
            }

        case .completed(let id):
            if let workout = workout(id) {
                TodayCompletedView(
                    workout: workout,
                    outcome: interpretation(for: workout)?.adherence,
                    explanation: explanation(for: workout)
                )
            }

        case .skipped(let id):
            TodayStatementView(
                heading: "\(disciplineName(id)) skipped",
                message: "Today's session was skipped.",
                detail: "Your remaining plan is unchanged.",
                actionTitle: "Adjust upcoming days",
                action: reshape
            )

        case .missed(let id):
            TodayStatementView(
                heading: "\(disciplineName(id)) not completed",
                message: "Today's session wasn't completed.",
                detail: "Your upcoming plan has not changed.",
                actionTitle: "Adjust upcoming days",
                action: reshape
            )

        case .restDay:
            TodayStatementView(
                heading: "Rest day",
                message: "No structured training today.",
                detail: nil
            )

        case .weekComplete:
            TodayStatementView(
                heading: "Week complete",
                message: "This week's training is done.",
                detail: "Your next week is created once you've reported this one."
            )
        }
    }

    private func recoveryWorkout(_ workout: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("RECOVERY WORKOUT", systemImage: workout.discipline.symbolName)
                .font(.headline)

            Text(workout.title)
                .font(.title2.weight(.semibold))

            if !workout.goal.isEmpty {
                Text(workout.goal)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            WorkoutPrescriptionView(workout: workout)

            Button("Complete recovery workout") {
                workout.completeWithoutFeedback()
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    private func feedbackNeeded(_ workout: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(
                    "\(workout.discipline.displayName.uppercased()) COMPLETE",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.headline)
                .foregroundStyle(AtheviaAdaptiveStyle(.green, gaming: .success))

                Spacer()

                Button {
                    sharingWorkout = workout
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

            Text("How did it feel?")
                .font(.title3.weight(.semibold))

            Button("Add your report") { feedbackWorkout = workout }
                .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    @ViewBuilder
    private var completedSummaries: some View {
        let finished = presentation.alsoCompletedToday.compactMap(workout)
        if !finished.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionEyebrow(text: "Also today")
                ForEach(finished) { workout in
                    NavigationLink {
                        WorkoutDayDetail(workout: workout)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AtheviaAdaptiveStyle(.green, gaming: .success))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.discipline.displayName)
                                    .font(.subheadline.weight(.medium))

                                if let summary = workout.importedSummary {
                                    Text(
                                        [
                                            TrainingFormatter.totalDuration(seconds: summary.duration),
                                            summary.distanceMeters.map { TrainingFormatter.distance(meters: $0) }
                                        ]
                                        .compactMap { $0 }
                                        .joined(separator: " · ")
                                    )
                                    .font(.caption)
                                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                }
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let scheduleMessage {
            Text(scheduleMessage)
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AtheviaAdaptiveStyle(.thinMaterial, gaming: .surface), in: .rect(cornerRadius: 12))
                .padding(.bottom, 12)
                .transition(.opacity)
        }
    }

    private var presentation: TodayPresentation {
        guard isResolved else { return .loading }

        let resolved = TodayPresentationBuilder.build(
            plan: plans.currentPlan(),
            finishedOnWatch: finishedOnWatch
        )

        if let activeID = PhoneWorkoutExecutionState.activeWorkoutID,
           workout(activeID) != nil {
            // Keep the subtree that owns the phone player's fullScreenCover
            // alive for the duration of execution. Background imports, Watch
            // refreshes, or other model updates must not replace it mid-run.
            return TodayPresentation(
                state: .upcoming(workoutID: activeID),
                next: resolved.next,
                alsoCompletedToday: resolved.alsoCompletedToday
            )
        }

        return resolved
    }

    private func workout(_ id: UUID) -> PlannedWorkout? {
        plans.currentPlan()?.orderedWorkouts.first { $0.id == id }
    }

    private var pendingCheckIn: PlannedWorkout? {
        plans.currentPlan()?.sessionAwaitingCheckIn()
    }

    private var checkInLeads: Bool {
        switch presentation.state {
        case .restDay, .weekComplete: true
        default: false
        }
    }

    private var eyebrow: String {
        switch presentation.state {
        case .upcoming, .needsFeedback, .completed, .awaitingImport: "Today's workout"
        default: "Today"
        }
    }

    private var intelligence: TrainingIntelligenceBuilder {
        TrainingIntelligenceBuilder(
            birthDate: profiles.first?.setup?.birthDate,
            observedMaximumHeartRate: summaries.compactMap(\.maximumHeartRate).max()
        )
    }

    private func disciplineName(_ id: UUID) -> String {
        workout(id)?.discipline.displayName ?? "Session"
    }

    private func interpretation(for workout: PlannedWorkout) -> WorkoutInterpretation? {
        let builder = intelligence
        guard let evidence = builder.evidence(from: workout, samples: []) else { return nil }

        let ceiling = builder.ceiling
        return WorkoutIntelligence.interpret(
            evidence,
            maximumHeartRate: ceiling?.maximum,
            zoneSource: ceiling?.source ?? .ageBasedMaximum
        )
    }

    private func explanation(for workout: PlannedWorkout) -> String? {
        guard let outcome = interpretation(for: workout)?.adherence else { return nil }

        let basis = workout.importedSummary != nil
            ? "Based on what your watch recorded."
            : "Based on your own report."

        return switch outcome.overall {
        case .withinTarget, .aboveTarget, .belowTarget: basis
        case .incomplete: "The session stopped short of the plan."
        case .skipped, .missed: nil
        }
    }

    private func refresh() async {
        guard scenePhase == .active else { return }

        await syncWatchState()

        if automaticallySchedule, let plan = plans.currentPlan() {
            // Watch scheduling remains for executable sport sessions only.
            // Recovery is completed on the phone because its walk + mobility
            // prescription is not a single WorkoutKit activity.
            await WatchScheduleSync.sync(plan, scheduler: scheduler)
            await syncWatchState()
        }
        isResolved = true
    }

    private func syncWatchState() async {
        let scheduled = await scheduler.scheduledWorkouts()
        scheduledWorkoutIDs = Set(scheduled.map(\.id))
        let activePhoneWorkoutID = PhoneWorkoutExecutionState.activeWorkoutID
        finishedOnWatch = Set(
            scheduled
                .filter { $0.isComplete && $0.id != activePhoneWorkoutID }
                .map(\.id)
        )
    }

    private func send(_ workout: PlannedWorkout) {
        guard workout.discipline.isTrainingSession else {
            scheduleMessage = "Recovery workouts are completed on iPhone."
            return
        }
        isScheduling = true
        ProductAnalytics.shared.track(.action(.sendToWatch, .requested))
        Task {
            defer { isScheduling = false }
            do {
                try await scheduler.schedule(workout, at: workout.suggestedScheduleDate())
                scheduledWorkoutIDs = await scheduler.scheduledWorkoutIDs()
                scheduleMessage = "Sent to your Apple Watch."
                ProductAnalytics.shared.track(.action(.sendToWatch, .succeeded))
            } catch {
                scheduleMessage = "Could not reach your Apple Watch."
                ProductAnalytics.shared.track(.action(.sendToWatch, .failed))
            }
        }
    }

    private func reshape() {
        guard let plan = plans.currentPlan(), let context = plan.modelContext else { return }
        ProductAnalytics.shared.track(.action(.updatePlan, .requested))
        do {
            _ = try PlanStore(context: context).reshapeWeek(plan)
            ProductAnalytics.shared.track(.action(.updatePlan, .succeeded))
            scheduleMessage = "Upcoming days updated."
            Task {
                await WatchScheduleSync.sync(plan, scheduler: scheduler)
                await syncWatchState()
            }
        } catch {
            scheduleMessage = "Could not adjust the upcoming days."
            ProductAnalytics.shared.track(.action(.updatePlan, .failed))
        }
    }
}
