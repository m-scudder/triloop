import Foundation
import Supabase

enum CoachLLMError: Error, LocalizedError, Equatable {
    case unavailable
    case invalidResponse
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "AI Coach is unavailable right now."
        case .invalidResponse:
            "AI Coach returned an invalid response."
        case .rejected(let message):
            message
        }
    }
}

struct CoachLLMWorkoutProposal: Codable, Equatable, Sendable {
    enum Focus: String, Codable, CaseIterable, Sendable {
        case easy
        case endurance
        case technique
        case intervals
    }

    let sport: Sport
    let focus: Focus
    let dateISO: String
    let targetMinutes: Int
    let goal: String
}

struct CoachLLMDeterministicIntent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case moveSession
        case skipSession
        case unavailable
        case unavailableRange
        case limitSession
        case easeSession
    }

    let kind: Kind
    let sourceDateISO: String?
    let targetDateISO: String?
    let endDateISO: String?
    let maxMinutes: Int?
    let easeReason: CoachEaseReason?
}

struct CoachLLMResponse: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case analysis
        case workoutProposal
        case deterministicIntent
    }

    let kind: Kind
    let message: String
    let evidence: [String]
    let workout: CoachLLMWorkoutProposal?
    let intent: CoachLLMDeterministicIntent?
}

private struct CoachLLMRequest: Encodable {
    let payload: String
}

struct CoachLLMService {
    var client: SupabaseClient = SupabaseConfiguration.client
    var functionName = "coach-llm"
    var maximumPayloadBytes = 64 * 1024

    func respond(
        request: String,
        context: AthleteContextSnapshot,
        currentPlan: WeeklyPlan,
        plans: [WeeklyPlan],
        recentMessages: [CoachChatMessage]
    ) async throws -> CoachLLMResponse {
        struct WorkoutPayload: Codable {
            let date: Date
            let discipline: Discipline
            let title: String
            let goal: String
            let status: PlannedWorkoutStatus
            let targetRPE: RPERange?
            let plannedDurationSeconds: TimeInterval?
            let plannedDistanceMeters: Double?
        }

        struct PlanPayload: Codable {
            let weekNumber: Int
            let startDate: Date
            let endDate: Date
            let workouts: [WorkoutPayload]
        }

        struct HealthWorkoutPayload: Codable {
            let sport: Sport
            let startDate: Date
            let endDate: Date
            let durationSeconds: TimeInterval
            let distanceMeters: Double?
            let longestContinuousSwimMeters: Double?
            let evidenceKind: CoachEvidenceKind
        }

        struct RecoveryPayload: Codable {
            let metric: String
            let value: Double
            let unit: String
            let observedAt: Date
            let sampleCount: Int
            let evidenceKind: CoachEvidenceKind
        }

        struct ContextPayload: Codable {
            let generatedAt: Date
            let windowStart: Date
            let windowEnd: Date
            let trainingObjective: TrainingObjective
            let experienceLevel: ExperienceLevel
            let baseline: CoachBaselineContext
            let availableSports: [Sport]
            let availability: [CoachAvailabilityContext]
            let capability: CoachCapabilityContext
            let recentWeeks: [CoachWeekHistoryContext]
            let recentHealthWorkouts: [HealthWorkoutPayload]
            let recoveryEvidence: [RecoveryPayload]
            let healthAccess: CoachHealthAccess
            let caveats: [String]
        }

        struct WorkoutHistoryPayload: Codable {
            let date: Date
            let title: String
            let discipline: Discipline
            let status: PlannedWorkoutStatus
            let plannedDurationSeconds: TimeInterval?
            let plannedDistanceMeters: Double?
            let actualDurationSeconds: TimeInterval?
            let actualDistanceMeters: Double?
            let averageHeartRate: Double?
            let reportedRPE: Int?
            let painScore: Int?
            let recoveryFeeling: RecoveryFeeling?
        }

        struct Payload: Codable {
            let request: String
            let context: ContextPayload
            let currentPlan: PlanPayload
            let recentWorkoutHistory: [WorkoutHistoryPayload]
            let recentMessages: [CoachLLMConversationTurn]
        }

        let historyWindowDays = CoachLLMContextCompactor.historyWindowDays(for: request)
        let maximumWorkoutRecords = CoachLLMContextCompactor.maximumWorkoutRecords(for: request)
        let historyCutoff = Calendar.current.date(
            byAdding: .day,
            value: -historyWindowDays,
            to: .now
        ) ?? .distantPast
        let history = plans
            .flatMap(\.orderedWorkouts)
            .filter { $0.date >= historyCutoff && $0.discipline.isPlannedWorkout }
            .sorted { $0.date > $1.date }
            .prefix(maximumWorkoutRecords)
            .map { workout in
                WorkoutHistoryPayload(
                    date: workout.date,
                    title: workout.title,
                    discipline: workout.discipline,
                    status: workout.status,
                    plannedDurationSeconds: workout.estimatedDurationSeconds,
                    plannedDistanceMeters: workout.estimatedDistanceMeters,
                    actualDurationSeconds: workout.importedSummary?.duration,
                    actualDistanceMeters: workout.importedSummary?.distanceMeters,
                    averageHeartRate: workout.importedSummary?.averageHeartRate,
                    reportedRPE: workout.feedback?.rpe,
                    painScore: workout.feedback?.painScore,
                    recoveryFeeling: workout.feedback?.recoveryFeeling
                )
            }

        guard CoachRequestScopeGuard.allows(request, recentMessages: recentMessages) else {
            throw CoachLLMError.rejected(
                "Athevia Coach can only help with your workout plan and workout history."
            )
        }

        let sanitizedContext = ContextPayload(
            generatedAt: context.generatedAt,
            windowStart: context.windowStart,
            windowEnd: context.windowEnd,
            trainingObjective: context.trainingObjective,
            experienceLevel: context.experienceLevel,
            baseline: context.baseline,
            availableSports: context.availableSports,
            availability: context.availability,
            capability: context.capability,
            recentWeeks: Array(context.recentWeeks.suffix(2)),
            recentHealthWorkouts: context.recentHealthWorkouts
                .filter { $0.endDate >= historyCutoff }
                .prefix(maximumWorkoutRecords)
                .map {
                HealthWorkoutPayload(
                    sport: $0.sport,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    durationSeconds: $0.durationSeconds,
                    distanceMeters: $0.distanceMeters,
                    longestContinuousSwimMeters: $0.longestContinuousSwimMeters,
                    evidenceKind: $0.evidenceKind
                )
            },
            recoveryEvidence: context.recoveryEvidence
                .sorted { $0.observedAt > $1.observedAt }
                .prefix(3)
                .map {
                RecoveryPayload(
                    metric: $0.metric,
                    value: $0.value,
                    unit: $0.unit,
                    observedAt: $0.observedAt,
                    sampleCount: $0.sampleCount,
                    evidenceKind: $0.evidenceKind
                )
            },
            healthAccess: context.healthAccess,
            caveats: context.caveats
        )

        let payload = Payload(
            request: CoachLLMContextCompactor.compact(request, limit: 600),
            context: sanitizedContext,
            currentPlan: PlanPayload(
                weekNumber: currentPlan.weekNumber,
                startDate: currentPlan.startDate,
                endDate: currentPlan.endDate,
                workouts: currentPlan.orderedWorkouts.map {
                    WorkoutPayload(
                        date: $0.date,
                        discipline: $0.discipline,
                        title: $0.title,
                        goal: $0.goal,
                        status: $0.status,
                        targetRPE: $0.targetRPE,
                        plannedDurationSeconds: $0.estimatedDurationSeconds,
                        plannedDistanceMeters: $0.estimatedDistanceMeters
                    )
                }
            ),
            recentWorkoutHistory: Array(history),
            recentMessages: CoachLLMContextCompactor.conversation(from: recentMessages)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        guard data.count <= maximumPayloadBytes else {
            throw CoachLLMError.rejected("The current training context is too large for AI analysis.")
        }

        guard let json = String(data: data, encoding: .utf8) else {
            throw CoachLLMError.invalidResponse
        }

        #if DEBUG
        if let localConfiguration = CoachLocalLLMConfiguration.current {
            print("[CoachAI] Local model is enabled")
            do {
                let response = try await CoachLocalLLMClient(
                    configuration: localConfiguration
                ).respond(payloadJSON: json)
                print("[CoachAI] Using local model response")
                return response
            } catch {
                print("[CoachAI] Local model failed: \(String(describing: error))")
                print("[CoachAI] Falling back to Supabase/OpenAI")
                // Debug local inference is best-effort. If the model server is
                // unavailable or returns an invalid shape, preserve the normal
                // authenticated Supabase/OpenAI path as fallback.
            }
        } else {
            print("[CoachAI] Local model is not configured; using Supabase/OpenAI")
        }
        #endif

        do {
            let data: Data = try await client.functions.invoke(
                functionName,
                options: FunctionInvokeOptions(
                    body: CoachLLMRequest(payload: json),
                    timeoutInterval: 20
                ),
                decode: { data, _ in data }
            )
            return try CoachLLMResponseGuard.decodeAndValidate(data)
        } catch let error as CoachLLMError {
            throw error
        } catch {
            throw CoachLLMError.unavailable
        }
    }
}
