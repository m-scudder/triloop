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
        struct PlanPayload: Codable {
            let id: UUID
            let weekNumber: Int
            let startDate: Date
            let endDate: Date
            let workouts: [CoachWorkoutSnapshot]
        }

        struct WorkoutHistoryPayload: Codable {
            let id: UUID
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
            let context: AthleteContextSnapshot
            let currentPlan: PlanPayload
            let recentWorkoutHistory: [WorkoutHistoryPayload]
            let recentMessages: [CoachChatMessage]
        }

        let historyCutoff = Calendar.current.date(byAdding: .day, value: -56, to: .now) ?? .distantPast
        let history = plans
            .flatMap(\.orderedWorkouts)
            .filter { $0.date >= historyCutoff && $0.discipline.isPlannedWorkout }
            .sorted { $0.date > $1.date }
            .prefix(40)
            .map { workout in
                WorkoutHistoryPayload(
                    id: workout.id,
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

        let payload = Payload(
            request: String(request.prefix(1_200)),
            context: context,
            currentPlan: PlanPayload(
                id: currentPlan.id,
                weekNumber: currentPlan.weekNumber,
                startDate: currentPlan.startDate,
                endDate: currentPlan.endDate,
                workouts: currentPlan.orderedWorkouts.map(CoachWorkoutSnapshot.init)
            ),
            recentWorkoutHistory: Array(history),
            recentMessages: Array(recentMessages.suffix(12))
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

        do {
            let response: CoachLLMResponse = try await client.functions.invoke(
                functionName,
                options: FunctionInvokeOptions(
                    body: CoachLLMRequest(payload: json),
                    timeoutInterval: 20
                )
            )
            return try validate(response)
        } catch {
            throw CoachLLMError.unavailable
        }
    }

    private func validate(_ response: CoachLLMResponse) throws -> CoachLLMResponse {
        let message = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 5_000 else {
            throw CoachLLMError.invalidResponse
        }

        switch response.kind {
        case .analysis:
            guard response.workout == nil, response.intent == nil else {
                throw CoachLLMError.invalidResponse
            }

        case .workoutProposal:
            guard let workout = response.workout,
                  response.intent == nil,
                  (10...180).contains(workout.targetMinutes),
                  !workout.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CoachLLMError.invalidResponse
            }

        case .deterministicIntent:
            guard response.intent != nil, response.workout == nil else {
                throw CoachLLMError.invalidResponse
            }
        }

        return response
    }
}
