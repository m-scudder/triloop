import SwiftData
import SwiftUI

/// Today answers one question: what does TriLoop want from me right now?
///
/// The screen is driven by `TodayPresentationState` rather than a stack of
/// conditionals, so exactly one thing leads and the priority is testable.
/// Analysis lives in Progress and Workout Detail; the week lives in Plan.
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
    @State private var checkInWorkout: PlannedWorkout?
    @State private var isResolved = false
    @State private var recovery = RecoverySignals()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.healthProvider) private var health

    private let scheduler = WorkoutKitScheduler()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let pending = pendingCheckIn {
                        if checkInLeads {
                            checkInCard(pending)
                        } else {
                            checkInPrompt(pending)
                        }
                    }
                    glance

                    VStack(alignment: .leading, spacing: 16) {
                        SectionEyebrow(text: eyebrow)
                        primary
                        nextFooter
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { profileButton }
            }
            .overlay(alignment: .bottom) { toast }
            .animation(.default, value: scheduleMessage)
            .sheet(item: $feedbackWorkout) { FeedbackSheet(workout: $0) }
            .sheet(item: $checkInWorkout) { RecoveryCheckInSheet(workout: $0) }
            // §30: an import while the app is open must move Today on without
            // the athlete pulling to refresh.
            .task(id: scenePhase) { await refresh() }
            // WorkoutKit drops a scheduled workout once its time has passed, so
            // a snapshot taken on launch goes out of date while Today is open.
            .onAppear { Task { await syncWatchState() } }
        }
    }

    // MARK: - Sections

    /// §10.1.1.2: the profile reached from Today rather than a fifth tab.
    @ViewBuilder
    private var profileButton: some View {
        if let profile = profiles.first {
            NavigationLink {
                TrainingProfileView(profile: profile)
            } label: {
                Group {
                    // The display name is optional, so there is not always a
                    // letter to show.
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
                .background(.fill.tertiary, in: .circle)
            }
            .accessibilityLabel("Training profile")
        }
    }

    private func monogram(of name: String) -> String? {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }

    /// §2: the week's shape, sized as context rather than as the subject.
    @ViewBuilder
    private var glance: some View {
        let tiles = TodayGlanceBuilder.tiles(
            plan: plans.currentPlan(),
            sessions: loadedSessions,
            recovery: recovery
        )
        if !tiles.isEmpty {
            TodayGlanceView(tiles: tiles)
        }
    }

    /// A banner, for days where today's own session is the headline.
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
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// On a day with no session the check-in is the only thing TriLoop wants,
    /// so it leads rather than sitting above the content as a banner.
    private func checkInCard(_ pending: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionEyebrow(text: "Yesterday")

            Text("How do you feel after \(pending.title)?")
                .font(.title3.weight(.medium))

            Text("Your answer is what decides how hard the coming days are.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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

        case .recoveryRequired:
            TodayStatementView(
                heading: "Recovery",
                message: "Training is paused today.",
                detail: "Your recent feedback asked for a recovery day. Nothing is expected of you."
            )

        case .needsFeedback(let id):
            if let workout = workout(id) {
                feedbackNeeded(workout)
            }

        case .upcoming(let id):
            if let workout = workout(id) {
                TodayWorkoutView(
                    workout: workout,
                    isScheduledOnWatch: scheduledWorkoutIDs.contains(workout.id),
                    isScheduling: isScheduling,
                    start: { send(workout) }
                )
                completedSummaries
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
                detail: "Recovery is part of the plan."
            )

        case .weekComplete:
            TodayStatementView(
                heading: "Week complete",
                message: "This week's training is done.",
                detail: "Your next week is created once you've reported this one."
            )
        }
    }

    private func feedbackNeeded(_ workout: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                "\(workout.discipline.displayName.uppercased()) COMPLETE",
                systemImage: "checkmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(.green)

            if let summary = workout.importedSummary {
                TodayMetricsRow(summary: summary, sport: workout.discipline.sport)
            }

            Text("How did it feel?")
                .font(.title3.weight(.semibold))

            Text("Your report is what decides next week's training.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Add your report") { feedbackWorkout = workout }
                .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    /// §28: finished sessions collapse while something else is outstanding.
    @ViewBuilder
    private var completedSummaries: some View {
        let finished = presentation.alsoCompletedToday.compactMap(workout)
        if !finished.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionEyebrow(text: "Also today")
                ForEach(finished) { workout in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(workout.title)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private var nextFooter: some View {
        if let next = presentation.next {
            TodayNextView(next: next, isLabelled: !presentation.state.isOutstanding)
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let scheduleMessage {
            Text(scheduleMessage)
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: .rect(cornerRadius: 12))
                .padding(.bottom, 12)
                .transition(.opacity)
        }
    }

    // MARK: - State

    private var presentation: TodayPresentation {
        // §29: nothing is claimed until the first resolve has run, so
        // "no workout today" cannot flash before the plan loads.
        guard isResolved else { return .loading }
        return TodayPresentationBuilder.build(
            plan: plans.currentPlan(),
            finishedOnWatch: finishedOnWatch
        )
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

    /// This week's sessions through the shared Phase 9.1 path. Heart-rate
    /// samples are left out on purpose: Today should not wait on HealthKit to
    /// draw four tiles, and effort alone classifies a session.
    private var loadedSessions: [LoadedSession] {
        guard let plan = plans.currentPlan() else { return [] }

        let builder = intelligence
        let ceiling = builder.ceiling

        return plan.trainingSessions.compactMap { workout in
            guard let evidence = builder.evidence(from: workout, samples: []) else { return nil }
            let interpretation = WorkoutIntelligence.interpret(
                evidence,
                maximumHeartRate: ceiling?.maximum,
                zoneSource: ceiling?.source ?? .ageBasedMaximum
            )
            return WorkoutIntelligence.session(from: evidence, interpretation: interpretation)
        }
    }

    private func disciplineName(_ id: UUID) -> String {
        workout(id)?.discipline.displayName ?? "Session"
    }

    /// §15: reuses the shared Phase 9.1 path rather than recomputing.
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

    /// §16: the wording must match the evidence that produced the verdict.
    ///
    /// The verdict compares planned against actual duration and distance, so
    /// its provenance is whether anything was imported — not whether an RPE
    /// exists, which by this point it always does.
    private func explanation(for workout: PlannedWorkout) -> String? {
        guard let outcome = interpretation(for: workout)?.adherence else { return nil }

        let basis = workout.importedSummary != nil
            ? "Based on what your watch recorded."
            : "Based on your own report."

        return switch outcome.overall {
        case .withinTarget: "You completed the planned session within target. \(basis)"
        case .aboveTarget: "Effort was higher than planned today. \(basis)"
        case .belowTarget: "This came in easier than planned. \(basis)"
        case .incomplete: "The session stopped short of the plan."
        case .skipped, .missed: nil
        }
    }

    // MARK: - Actions

    private func refresh() async {
        guard scenePhase == .active else { return }

        await syncWatchState()

        if automaticallySchedule, let plan = plans.currentPlan() {
            await WatchScheduleSync.sync(plan, scheduler: scheduler)
            await syncWatchState()
        }
        isResolved = true
        await loadRecovery()
    }

    private func syncWatchState() async {
        let scheduled = await scheduler.scheduledWorkouts()
        scheduledWorkoutIDs = Set(scheduled.map(\.id))
        finishedOnWatch = Set(scheduled.filter(\.isComplete).map(\.id))
    }

    /// Runs after `isResolved` so the screen is never held back by HealthKit;
    /// the recovery tile appears when it can.
    private func loadRecovery() async {
        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -28, to: end) else { return }

        var collected: [RecoveryMetricKey: [RecoveryReading]] = [:]
        for metric in RecoveryMetric.allCases {
            guard let key = RecoveryMetricKey(rawValue: metric.rawValue) else { continue }
            let points = (try? await health.recoverySeries(metric, from: start, to: end)) ?? []
            collected[key] = points.map { RecoveryReading(date: $0.date, value: $0.value) }
        }

        recovery = TrainingSignalsBuilder.build(
            weeks: [],
            recovery: collected,
            asOf: end
        ).recovery
    }

    private func send(_ workout: PlannedWorkout) {
        isScheduling = true
        Task {
            defer { isScheduling = false }
            do {
                try await scheduler.schedule(workout, at: workout.suggestedScheduleDate())
                scheduledWorkoutIDs = await scheduler.scheduledWorkoutIDs()
                scheduleMessage = "Sent to your Apple Watch."
            } catch {
                scheduleMessage = "Could not reach your Apple Watch."
            }
        }
    }

    /// Never prompts. Automatic scheduling stays silent until the athlete has
    /// already granted permission through the explicit action.
    private func reshape() {
        guard let plan = plans.currentPlan(), let context = plan.modelContext else { return }
        do {
            _ = try PlanStore(context: context).reshapeWeek(plan)
            scheduleMessage = "Upcoming days updated."
            Task {
                await WatchScheduleSync.sync(plan, scheduler: scheduler)
                await syncWatchState()
            }
        } catch {
            scheduleMessage = "Could not adjust the upcoming days."
        }
    }
}
