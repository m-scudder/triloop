import Foundation

/// What Today should lead with.
///
/// One deterministic answer to "what matters right now", derived from existing
/// domain state. Keeping it out of the view means the priority in §27 is
/// testable rather than an accident of SwiftUI ordering.
enum TodayPresentationState: Equatable {
    /// Nothing decided yet. Prevents "no workout today" flashing before the
    /// plan and any import have resolved (§29).
    case loading
    case noPlan

    /// Training is deliberately paused. Outranks everything else.
    case recoveryRequired(workoutID: UUID)
    /// Done, but TriLoop still needs the athlete's report.
    case needsFeedback(workoutID: UUID)
    /// The Watch says it is finished; Health has not delivered it yet.
    case awaitingImport(workoutID: UUID)
    /// Still to do today. A remaining session outranks a finished one (§28).
    case upcoming(workoutID: UUID)
    case completed(workoutID: UUID)
    case skipped(workoutID: UUID)
    case missed(workoutID: UUID)
    case restDay
    /// The plan has run out of days rather than the athlete running out of work.
    case weekComplete
}

/// A session on a future day, shown as light context (§10).
struct NextSession: Equatable {
    let workoutID: UUID
    let discipline: Discipline
    let date: Date
    let durationSeconds: TimeInterval?
}

/// Everything Today needs, resolved once.
struct TodayPresentation: Equatable {
    let state: TodayPresentationState
    let next: NextSession?
    /// Finished sessions from today, collapsed to summaries when another
    /// session is still outstanding.
    let alsoCompletedToday: [UUID]

    static let loading = TodayPresentation(state: .loading, next: nil, alsoCompletedToday: [])
    static let noPlan = TodayPresentation(state: .noPlan, next: nil, alsoCompletedToday: [])
}

/// Resolves the one thing Today should say.
enum TodayPresentationBuilder {

    static func build(
        plan: WeeklyPlan?,
        finishedOnWatch: Set<UUID> = [],
        date: Date = .now,
        calendar: Calendar = .current
    ) -> TodayPresentation {
        guard let plan else { return .noPlan }

        let today = calendar.startOfDay(for: date)
        let todaysWorkouts = plan.orderedWorkouts.filter {
            calendar.isDate($0.date, inSameDayAs: today)
        }

        let next = nextSession(in: plan, after: today, calendar: calendar)
        let completedToday = todaysWorkouts.filter(\.isCompleted).map(\.id)

        guard !todaysWorkouts.isEmpty else {
            // A day the plan never covered: past the end of the week, or before
            // it began.
            return TodayPresentation(
                state: next == nil ? .weekComplete : .restDay,
                next: next,
                alsoCompletedToday: []
            )
        }

        let state = resolveState(
            todaysWorkouts,
            finishedOnWatch: finishedOnWatch,
            asOf: date,
            calendar: calendar
        )

        return TodayPresentation(
            state: state,
            next: next,
            // Only worth listing when something else still needs doing.
            alsoCompletedToday: state.isOutstanding ? completedToday : []
        )
    }

    /// §27's priority, applied in order.
    private static func resolveState(
        _ workouts: [PlannedWorkout],
        finishedOnWatch: Set<UUID>,
        asOf date: Date,
        calendar: Calendar
    ) -> TodayPresentationState {
        if let recovery = workouts.first(where: { $0.discipline == .recovery }) {
            return .recoveryRequired(workoutID: recovery.id)
        }

        let sessions = workouts.filter(\.discipline.isTrainingSession)
        guard !sessions.isEmpty else { return .restDay }

        // Feedback outranks a remaining session: closing the loop on work
        // already done is what keeps the engine honest.
        if let awaiting = sessions.first(where: { $0.isCompleted && !$0.hasReport }) {
            return .needsFeedback(workoutID: awaiting.id)
        }

        // Finished on the Watch but not yet imported. Offering "Start" here
        // would invite a second recording of a session already done.
        if let syncing = sessions.first(where: {
            !$0.isCompleted && !$0.isSkipped && finishedOnWatch.contains($0.id)
        }) {
            return .awaitingImport(workoutID: syncing.id)
        }

        if let outstanding = sessions.first(where: {
            !$0.isCompleted && !$0.isSkipped && !$0.isMissed(asOf: date, calendar: calendar)
        }) {
            return .upcoming(workoutID: outstanding.id)
        }

        if let completed = sessions.first(where: { $0.isCompleted }) {
            return .completed(workoutID: completed.id)
        }

        if let skipped = sessions.first(where: \.isSkipped) {
            return .skipped(workoutID: skipped.id)
        }

        if let missed = sessions.first(where: { $0.isMissed(asOf: date, calendar: calendar) }) {
            return .missed(workoutID: missed.id)
        }

        return .restDay
    }

    private static func nextSession(
        in plan: WeeklyPlan,
        after today: Date,
        calendar: Calendar
    ) -> NextSession? {
        guard let workout = plan.orderedWorkouts.first(where: {
            calendar.startOfDay(for: $0.date) > today && $0.discipline.isTrainingSession
        }) else { return nil }

        return NextSession(
            workoutID: workout.id,
            discipline: workout.discipline,
            date: workout.date,
            durationSeconds: workout.prescribedDurationSeconds ?? workout.estimatedDurationSeconds
        )
    }
}

extension TodayPresentationState {
    /// Whether the athlete still has something to do or say today.
    var isOutstanding: Bool {
        switch self {
        case .upcoming, .needsFeedback, .awaitingImport: true
        case .loading, .noPlan, .recoveryRequired, .completed, .skipped, .missed, .restDay, .weekComplete: false
        }
    }

    var workoutID: UUID? {
        switch self {
        case .recoveryRequired(let id), .needsFeedback(let id), .upcoming(let id),
             .awaitingImport(let id), .completed(let id), .skipped(let id), .missed(let id):
            id
        case .loading, .noPlan, .restDay, .weekComplete:
            nil
        }
    }
}
