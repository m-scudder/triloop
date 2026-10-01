import Foundation

enum CoachRemoteTransportError: Error, Equatable {
    case timedOut
    case contextTooLarge
    case invalidResponse
    case rateLimited
}

actor CoachRemoteRateGate {
    static let shared = CoachRemoteRateGate()

    let maximumRequests: Int
    let windowSeconds: TimeInterval
    private var requestsByAthlete: [String: [Date]] = [:]

    init(maximumRequests: Int = 6, windowSeconds: TimeInterval = 60) {
        self.maximumRequests = maximumRequests
        self.windowSeconds = windowSeconds
    }

    func allow(athleteScopeID: String, at now: Date = .now) -> Bool {
        let cutoff = now.addingTimeInterval(-windowSeconds)
        var recent = requestsByAthlete[athleteScopeID, default: []]
            .filter { $0 >= cutoff }
        guard recent.count < maximumRequests else {
            requestsByAthlete[athleteScopeID] = recent
            return false
        }
        recent.append(now)
        requestsByAthlete[athleteScopeID] = recent
        return true
    }
}

/// Server-backed implementations must authenticate the athlete, enforce
/// authorization/rate limits, and return only the strict intent JSON schema.
/// This client boundary intentionally has no API key or provider-specific code.
protocol CoachRemoteIntentTransport: Sendable {
    func classify(
        request: String,
        boundedContextJSON: Data
    ) async throws -> Data
}

/// Routes conversation understanding through an optional remote classifier while
/// preserving a deterministic on-device fallback. Remote output can select only
/// an allowlisted intent; the domain engine remains authoritative.
struct CoachConversationRouter: Sendable {
    var remote: (any CoachRemoteIntentTransport)?
    var local = DeterministicCoachIntentInterpreter()
    var timeoutSeconds: Double = 8
    var maximumContextBytes = 64 * 1024
    var rateGate = CoachRemoteRateGate.shared

    func interpret(
        request: String,
        context: AthleteContextSnapshot,
        plan: WeeklyPlan,
        now: Date,
        externalAIConsent: Bool
    ) async -> CoachIntentInterpretation {
        guard externalAIConsent, let remote else {
            return await local.interpret(
                request: request,
                context: context,
                plan: plan,
                now: now
            )
        }

        do {
            guard await rateGate.allow(athleteScopeID: context.athleteScopeID) else {
                throw CoachRemoteTransportError.rateLimited
            }
            let payload = try contextPayload(context)
            let raw = try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await remote.classify(
                        request: String(request.prefix(600)),
                        boundedContextJSON: payload
                    )
                }
                group.addTask {
                    let nanos = UInt64(max(timeoutSeconds, 0.1) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanos)
                    throw CoachRemoteTransportError.timedOut
                }

                guard let first = try await group.next() else {
                    throw CoachRemoteTransportError.invalidResponse
                }
                group.cancelAll()
                return first
            }

            let envelope = try CoachModelResponseDecoder.decode(raw)
            let intent = try CoachModelResponseDecoder.intent(from: envelope)
            return .intent(intent)
        } catch {
            if Task.isCancelled {
                return .unsupported("Coach request was cancelled.")
            }
            // Offline, timeout, schema violations and server errors all fall
            // back to the deterministic supported-request interpreter. No
            // model output is executed.
            return await local.interpret(
                request: request,
                context: context,
                plan: plan,
                now: now
            )
        }
    }

    private func contextPayload(_ context: AthleteContextSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(context)
        guard data.count <= maximumContextBytes else {
            throw CoachRemoteTransportError.contextTooLarge
        }
        return data
    }
}
