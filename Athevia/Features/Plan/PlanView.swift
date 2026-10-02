import SwiftData
import SwiftUI

/// Date-led view of the plan: pick a day and work with that session in place.
///
/// Home owns workout execution. Plan owns prescription, completed analysis and
/// schedule management, so there is no extra workout-detail navigation step.
struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @Query(sort: \PlannedWorkout.date) private var storedWorkouts: [PlannedWorkout]
    @Query private var profiles: [AthleteProfile]

    @State private var selection: Date = .now
    @State private var isPresentingCalendar = false
    @State private var hasChosenOpeningDay = false
    @State private var focused: UUID?

    /// Plan is one calendar for both prescriptions and real training history.
    /// Generated/library sessions come from WeeklyPlan; standalone imported
    /// Run/Swim/Cycle can predate the first plan after a reset.
    private var allWorkouts: [PlannedWorkout] {
        storedWorkouts
            .filter { workout in
                workout.plan != nil
                    || (
                        workout.origin == .imported
                            && workout.plan == nil
                            && workout.discipline.sport != nil
                    )
            }
            .sorted { lhs, rhs in
                if Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) {
                    // Prescription first; completed imported activity follows.
                    if lhs.origin != rhs.origin {
                        return lhs.origin != .imported
                    }
                    return lhs.completedAt ?? lhs.date < rhs.completedAt ?? rhs.date
                }
                return lhs.date < rhs.date
            }
    }

    private var workoutsOnSelectedDay: [PlannedWorkout] {
        allWorkouts.filter { Calendar.current.isDate($0.date, inSameDayAs: selection) }
    }

    private var selectedWorkout: PlannedWorkout? {
        let onTheDay = workoutsOnSelectedDay
        return onTheDay.first { $0.id == focused } ?? onTheDay.first
    }

    private var sessionBinding: Binding<UUID?> {
        Binding(
            get: { selectedWorkout?.id },
            set: { focused = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if allWorkouts.isEmpty {
                    ContentUnavailableView(
                        "No plan yet",
                        systemImage: "calendar",
                        description: Text("Your first training week has not been generated.")
                    )
                } else {
                    VStack(spacing: 0) {
                        if let setup = profiles.first?.setup,
                           setup.objective.event?.eventDate != nil {
                            EventCountdownView(objective: setup.objective)
                                .padding(.horizontal, 20)
                                .padding(.top, 10)

                            let journey = TrainingJourneyPlanner().plan(
                                setup: setup,
                                recentPlans: Array(plans.suffix(4))
                            )
                            if let focus = journey.primaryFocus {
                                HStack {
                                    Text("This week's focus")
                                    Spacer()
                                    Text(focus.kind.displayName)
                                }
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                            }

                            NavigationLink {
                                FullTrainingJourneyView(
                                    setup: setup,
                                    plans: plans
                                )
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                        .font(.subheadline.weight(.semibold))

                                    Text("Race plan")
                                        .font(.subheadline.weight(.semibold))

                                    Spacer()

                                    if let weeks = journey.weeksRemaining {
                                        Text("\(weeks) wk")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                    }

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(
                                    AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface),
                                    in: .rect(cornerRadius: 12)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                            Divider()
                        }

                        DateStrip(workouts: allWorkouts, selection: $selection)

                        Divider()

                        if workoutsOnSelectedDay.count > 1 {
                            Picker("Session", selection: sessionBinding) {
                                ForEach(workoutsOnSelectedDay) { workout in
                                    Text(workout.title).tag(workout.id)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }

                        if let workout = selectedWorkout {
                            WorkoutDayDetail(
                                workout: workout,
                                showsManagementMenu: true
                            )
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                PlanWatchAction(workout: workout)
                            }
                            .id(workout.id)
                        } else {
                            ContentUnavailableView(
                                "Nothing planned",
                                systemImage: "moon.zzz",
                                description: Text("There is no session on this date.")
                            )
                        }
                    }
                }
            }
            .atheviaScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .analyticsScreen(.plan)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WorkoutLibraryView()
                    } label: {
                        Label("Workouts", systemImage: "square.grid.2x2")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingCalendar = true
                        ProductAnalytics.shared.track(.calendarOpened)
                    } label: {
                        Label("Choose a date", systemImage: "calendar")
                    }
                }
            }
            .sheet(isPresented: $isPresentingCalendar) {
                calendarSheet
            }
            .onAppear {
                try? PlanStore(context: modelContext).normalizeWorkoutTitles()
                selectSensibleDay()
            }
        }
        .atheviaScreen()
    }

    private var title: String {
        TrainingFormatter.shortDate(selection)
    }

    private var calendarSheet: some View {
        DatePicker(
            "Date",
            selection: $selection,
            in: dateRange,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(.horizontal, 12)
        .onChange(of: selection) { isPresentingCalendar = false }
        .presentationDetents([.medium])
    }

    private var dateRange: ClosedRange<Date> {
        let dates = allWorkouts.map(\.date)
        guard let first = dates.min(), let last = dates.max() else {
            return Date.now...Date.now
        }
        return first...max(last, first)
    }

    private func selectSensibleDay() {
        guard !hasChosenOpeningDay, !allWorkouts.isEmpty else { return }
        hasChosenOpeningDay = true

        let calendar = Calendar.current
        if allWorkouts.contains(where: { calendar.isDateInToday($0.date) }) {
            selection = .now
            return
        }
        let now = Date.now
        let nearest = allWorkouts.min {
            abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now))
        }
        if let nearest { selection = nearest.date }
    }
}

/// Kept on Plan so the selected session has a visible Watch action above the tabs.
private struct PlanWatchAction: View {
    let workout: PlannedWorkout
    var scheduler: any WorkoutScheduling = WorkoutKitScheduler()

    @StateObject private var watch = WatchAvailability.shared
    @State private var isSending = false
    @State private var message: String?
    @State private var finishedOnWatch = false
    @State private var isScheduledOnWatch = false
    @State private var isCheckingWatch = true
    @Environment(\.scenePhase) private var scenePhase

    private var canSend: Bool {
        watch.canSchedule && scheduler.isSupported
            && workout.discipline.isTrainingSession
            && !workout.isCompleted
            && !workout.isSkipped
            && !workout.hasReport
            && workout.importedSummary == nil
            && !finishedOnWatch
    }

    var body: some View {
        Group {
            if canSend && !isScheduledOnWatch {
                VStack(spacing: 0) {
                    Divider()
                    Button(action: send) {
                        HStack(spacing: 8) {
                            if isSending || isCheckingWatch {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "applewatch")
                            }
                            Text(watchActionTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(isSending || isCheckingWatch)
                    .accessibilityIdentifier("plan.sendToWatch")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    if isScheduledOnWatch {
                        Text("Scheduled. Watch sync may still be pending.")
                            .font(.caption)
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }
                }
                .background(AtheviaAdaptiveStyle(.regularMaterial, gaming: .surface))
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            watch.refresh()
            await refreshWatchStatus()
        }
        .alert("Apple Watch", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var watchActionTitle: String {
        if isSending { return "Sending…" }
        if isCheckingWatch { return "Checking…" }
        return "Send to Watch"
    }

    @MainActor
    private func refreshWatchStatus() async {
        guard !isSending else { return }
        isCheckingWatch = true
        defer { isCheckingWatch = false }
        let entries = await scheduler.scheduledWorkouts()
        // A send may have started while the query was suspended.
        guard !Task.isCancelled, !isSending else { return }
        let matching = entries.filter { $0.id == workout.id }
        isScheduledOnWatch = !matching.isEmpty
        finishedOnWatch = matching.contains(where: \.isComplete)
    }

    private func send() {
        guard canSend, !isSending, !isCheckingWatch, !isScheduledOnWatch else { return }
        isSending = true
        ProductAnalytics.shared.track(.action(.sendToWatch, .requested))
        Task { @MainActor in
            var outcome: AnalyticsOutcome = .failed
            defer {
                isSending = false
                ProductAnalytics.shared.track(.action(.sendToWatch, outcome))
            }
            do {
                guard scheduler.isSupported else { throw WorkoutSchedulingError.unavailable }
                guard WorkoutPlanBuilder.plan(for: workout) != nil else {
                    throw WorkoutSchedulingError.unsupportedWorkout
                }
                guard await scheduler.requestAuthorization() == .authorized else {
                    throw WorkoutSchedulingError.notAuthorized
                }

                let entries = await scheduler.scheduledWorkouts().filter { $0.id == workout.id }
                if entries.contains(where: \.isComplete) {
                    outcome = .cancelled
                    finishedOnWatch = true
                    message = "This workout is already complete on your Watch. Its details are waiting to sync."
                    return
                }
                guard canSend else {
                    outcome = .cancelled
                    return
                }

                // Explicitly resend the selected session, replacing its old copy
                // so repeated taps cannot accumulate different scheduled times.
                let existingDate = entries.compactMap(\.date).first {
                    Calendar.current.isDate($0, inSameDayAs: workout.date)
                }
                if !entries.isEmpty {
                    await scheduler.removeScheduled(ids: [workout.id])
                }
                try await scheduler.schedule(
                    workout,
                    at: existingDate ?? workout.suggestedScheduleDate()
                )
                isScheduledOnWatch = true
                outcome = .succeeded
                message = "Scheduled for your Apple Watch. Look for “\(WorkoutPlanBuilder.displayName(for: workout))” in the Workout app after it syncs."
            } catch WorkoutSchedulingError.unavailable {
                message = "Workout scheduling is unavailable. Check that an Apple Watch is paired with this iPhone."
            } catch WorkoutSchedulingError.notAuthorized {
                message = "Allow Athevia to add workouts in your Apple Watch Workout settings, then try again."
            } catch WorkoutSchedulingError.unsupportedWorkout {
                message = "This workout cannot be sent to Apple Watch."
            } catch {
                message = "The workout could not be scheduled. Check your Watch connection and try again."
            }
        }
    }
}

#if DEBUG
#Preview {
    PlanView()
        .modelContainer(PreviewData.container)
}
#endif
