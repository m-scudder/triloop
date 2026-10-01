import Foundation

/// The only requests the conversational layer is allowed to hand to the
/// training domain. A model may classify language into these values, but it
/// never authors workout structure or writes training state directly.
enum CoachIntent: Codable, Equatable, Sendable {
    case explainWorkout(date: Date)
    case summarizeRecentTraining(weeks: Int)
    case limitSession(date: Date, maxMinutes: Int)
    case unavailable(date: Date)
    case easeSession(date: Date, reason: CoachEaseReason)
    case moveSession(from: Date, to: Date)
    case skipSession(date: Date)
    case unavailableRange(start: Date, end: Date)
    case prepareFor5K(eventDate: Date?)
}

enum CoachEaseReason: String, Codable, Equatable, Sendable {
    case tired
    case poorSleep
    case general
}

enum CoachIntentInterpretation: Equatable, Sendable {
    case intent(CoachIntent)
    case clarification(String)
    case unsupported(String)
}

enum CoachConfirmationState: String, Codable, Equatable, Sendable {
    case awaitingConfirmation
    case applied
    case cancelled
    case stale
}

enum CoachValidationStatus: String, Codable, Equatable, Sendable {
    case valid
    case blocked
}

struct CoachActionValidationResult: Codable, Equatable, Sendable {
    let status: CoachValidationStatus
    let validatedAt: Date
    let checks: [String]
    let blockers: [String]

    static func valid(at date: Date, checks: [String]) -> CoachActionValidationResult {
        CoachActionValidationResult(
            status: .valid,
            validatedAt: date,
            checks: checks,
            blockers: []
        )
    }
}

struct CoachReshapeExpectation: Codable, Equatable, Sendable {
    let workoutID: UUID
    let date: Date
    let discipline: Discipline
    let skipped: Bool

    init(_ change: PlanReshaper.Change) {
        workoutID = change.workoutID
        date = change.date
        discipline = change.discipline
        skipped = change.skipped
    }
}

/// A persistence-free copy of a prescription. It intentionally excludes
/// feedback, imported evidence and recovery reports so a coach action cannot
/// overwrite completed history.
struct CoachWorkoutSnapshot: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var date: Date
    var discipline: Discipline
    var title: String
    var goal: String
    var targetRPE: RPERange?
    var prescribedDurationSeconds: TimeInterval?
    var targetDistanceMeters: Double?
    var status: PlannedWorkoutStatus
    var structure: WorkoutStructure

    init(_ workout: PlannedWorkout) {
        id = workout.id
        date = workout.date
        discipline = workout.discipline
        title = workout.title
        goal = workout.goal
        targetRPE = workout.targetRPE
        prescribedDurationSeconds = workout.prescribedDurationSeconds
        targetDistanceMeters = workout.targetDistanceMeters
        status = workout.status
        structure = WorkoutStructure(steps: workout.orderedSteps)
    }

    var estimatedDurationSeconds: TimeInterval? {
        prescribedDurationSeconds ?? structure.totalDurationSeconds
    }

    var estimatedDistanceMeters: Double? {
        targetDistanceMeters ?? structure.totalDistanceMeters
    }

    func makeWorkout() -> PlannedWorkout {
        PlannedWorkout(
            id: id,
            date: date,
            discipline: discipline,
            title: title,
            goal: goal,
            targetRPE: targetRPE,
            prescribedDurationSeconds: prescribedDurationSeconds,
            targetDistanceMeters: targetDistanceMeters,
            status: status,
            steps: structure.makeSteps()
        )
    }
}

enum CoachWorkoutChangeKind: String, Codable, Equatable, Sendable {
    case moved
    case shortened
    case eased
    case skipped
    case replanned
}

struct CoachWorkoutChange: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let kind: CoachWorkoutChangeKind
    let before: CoachWorkoutSnapshot?
    let after: CoachWorkoutSnapshot?
    let reason: String

    init(
        id: UUID = UUID(),
        kind: CoachWorkoutChangeKind,
        before: CoachWorkoutSnapshot?,
        after: CoachWorkoutSnapshot?,
        reason: String
    ) {
        self.id = id
        self.kind = kind
        self.before = before
        self.after = after
        self.reason = reason
    }
}

/// An auditable action that is still data until Apply is explicitly confirmed.
enum CoachPlanAction: Codable, Equatable, Sendable {
    case replaceWorkout(
        workoutID: UUID,
        replacement: CoachWorkoutSnapshot,
        generationReason: PlanGenerationReason
    )
    case reshapeWeek(
        temporarySchedule: AthleteSchedule,
        expectedChanges: [CoachReshapeExpectation]
    )
    case changeObjective(
        before: TrainingObjective,
        after: TrainingObjective
    )
    case addWorkout(
        workout: CoachWorkoutSnapshot,
        generationReason: PlanGenerationReason
    )
}

struct CoachPlanChangePreview: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let originalRequest: String
    let interpretedIntent: CoachIntent
    let interpretedConstraints: [String]
    let athleteScopeID: String
    let contextVersion: String
    let basePlanVersion: String
    let planID: UUID
    let generatedAt: Date
    let changes: [CoachWorkoutChange]
    let reasons: [String]
    let action: CoachPlanAction
    let validation: CoachActionValidationResult
    var confirmationState: CoachConfirmationState

    init(
        id: UUID = UUID(),
        originalRequest: String,
        interpretedIntent: CoachIntent,
        interpretedConstraints: [String],
        athleteScopeID: String,
        contextVersion: String,
        basePlanVersion: String,
        planID: UUID,
        generatedAt: Date,
        changes: [CoachWorkoutChange],
        reasons: [String],
        action: CoachPlanAction,
        validation: CoachActionValidationResult,
        confirmationState: CoachConfirmationState = .awaitingConfirmation
    ) {
        self.id = id
        self.originalRequest = originalRequest
        self.interpretedIntent = interpretedIntent
        self.interpretedConstraints = interpretedConstraints
        self.athleteScopeID = athleteScopeID
        self.contextVersion = contextVersion
        self.basePlanVersion = basePlanVersion
        self.planID = planID
        self.generatedAt = generatedAt
        self.changes = changes
        self.reasons = reasons
        self.action = action
        self.validation = validation
        self.confirmationState = confirmationState
    }
}

struct CoachDomainResponse: Equatable, Sendable {
    var message: String
    var evidenceSummary: String
    var preview: CoachPlanChangePreview?
}

/// Stable across launches unlike Swift's Hashable random seed. This is a change
/// detector, not a cryptographic integrity primitive.
enum CoachStableFingerprint {
    static func value<T: Encodable>(for value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(value) else { return "unavailable" }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

enum CoachPlanVersion {
    private struct Payload: Codable {
        let id: UUID
        let weekNumber: Int
        let startDate: Date
        let endDate: Date
        let status: WeeklyPlanStatus
        let generatedAt: Date
        let generationReason: String
        let generationReasonCode: PlanGenerationReason?
        let parameters: TrainingParameters
        let workouts: [CoachWorkoutSnapshot]
    }

    static func fingerprint(_ plan: WeeklyPlan) -> String {
        CoachStableFingerprint.value(
            for: Payload(
                id: plan.id,
                weekNumber: plan.weekNumber,
                startDate: plan.startDate,
                endDate: plan.endDate,
                status: plan.status,
                generatedAt: plan.generatedAt,
                generationReason: plan.generationReason,
                generationReasonCode: plan.generationReasonCode,
                parameters: plan.parameters,
                workouts: plan.orderedWorkouts.map(CoachWorkoutSnapshot.init)
            )
        )
    }
}

/// Minimal schema a future remote language model may return. It cannot contain
/// workout steps, SQL, arbitrary actions or persistence instructions.
struct CoachModelIntentEnvelope: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case explainWorkout
        case summarizeRecentTraining
        case limitSession
        case unavailable
        case easeSession
        case prepareFor5K
    }

    var kind: Kind
    var targetDate: Date?
    var maxMinutes: Int?
    var weeks: Int?
    var easeReason: CoachEaseReason?
    var eventDate: Date?
}

enum CoachModelResponseError: Error, Equatable {
    case malformed
    case unknownField(String)
    case invalidArguments
}

/// Extra JSON keys are rejected rather than ignored. Model output is untrusted
/// input and must fit the allowlisted intent contract exactly.
enum CoachModelResponseDecoder {
    private static let allowedKeys: Set<String> = [
        "kind", "targetDate", "maxMinutes", "weeks", "easeReason", "eventDate"
    ]

    static func decode(_ data: Data) throws -> CoachModelIntentEnvelope {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw CoachModelResponseError.malformed
        }

        for key in dictionary.keys where !allowedKeys.contains(key) {
            throw CoachModelResponseError.unknownField(key)
        }

        do {
            return try JSONDecoder().decode(CoachModelIntentEnvelope.self, from: data)
        } catch {
            throw CoachModelResponseError.malformed
        }
    }

    static func intent(from envelope: CoachModelIntentEnvelope) throws -> CoachIntent {
        switch envelope.kind {
        case .explainWorkout:
            guard let date = envelope.targetDate else { throw CoachModelResponseError.invalidArguments }
            return .explainWorkout(date: date)
        case .summarizeRecentTraining:
            let weeks = min(max(envelope.weeks ?? 4, 1), 8)
            return .summarizeRecentTraining(weeks: weeks)
        case .limitSession:
            guard let date = envelope.targetDate,
                  let minutes = envelope.maxMinutes,
                  (10...240).contains(minutes) else {
                throw CoachModelResponseError.invalidArguments
            }
            return .limitSession(date: date, maxMinutes: minutes)
        case .unavailable:
            guard let date = envelope.targetDate else { throw CoachModelResponseError.invalidArguments }
            return .unavailable(date: date)
        case .easeSession:
            guard let date = envelope.targetDate else { throw CoachModelResponseError.invalidArguments }
            return .easeSession(date: date, reason: envelope.easeReason ?? .general)
        case .prepareFor5K:
            return .prepareFor5K(eventDate: envelope.eventDate)
        }
    }
}

protocol CoachConversationInterpreting: Sendable {
    func interpret(
        request: String,
        context: AthleteContextSnapshot,
        plan: WeeklyPlan,
        now: Date
    ) async -> CoachIntentInterpretation
}

/// Deliberately unavailable until an authenticated server-side model proxy is
/// approved and configured. No LLM secret is ever accepted by the iOS client.
struct DisabledExternalCoachConversationService: CoachConversationInterpreting {
    func interpret(
        request: String,
        context: AthleteContextSnapshot,
        plan: WeeklyPlan,
        now: Date
    ) async -> CoachIntentInterpretation {
        .unsupported("External AI interpretation is not configured. Athevia can still use its on-device supported coach requests.")
    }
}
