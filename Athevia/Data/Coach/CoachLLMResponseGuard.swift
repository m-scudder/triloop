import Foundation

enum CoachLLMResponseGuard {
    private static let topLevelKeys: Set<String> = [
        "kind", "message", "evidence", "workout", "intent"
    ]
    private static let workoutKeys: Set<String> = [
        "sport", "focus", "dateISO", "targetMinutes", "goal"
    ]
    private static let intentKeys: Set<String> = [
        "kind", "sourceDateISO", "targetDateISO", "endDateISO", "maxMinutes", "easeReason"
    ]

    private static let forbiddenFragments = [
        "system prompt",
        "developer message",
        "hidden instruction",
        "api key",
        "secret key",
        "service_role",
        "authorization: bearer",
        "database schema",
        "source code",
        "git repository",
        "swiftdata model",
        "supabase url",
        "environment variable",
        "begin system",
        "ignore previous instructions"
    ]

    static func decodeAndValidate(_ data: Data) throws -> CoachLLMResponse {
        guard data.count <= 32 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw CoachLLMError.invalidResponse
        }

        try requireExactKeys(
            dictionary,
            allowed: topLevelKeys,
            required: ["kind", "message", "evidence"]
        )

        guard let kindRaw = dictionary["kind"] as? String,
              let kind = CoachLLMResponse.Kind(rawValue: kindRaw),
              let message = dictionary["message"] as? String,
              let evidence = dictionary["evidence"] as? [String] else {
            throw CoachLLMError.invalidResponse
        }

        try validateUserFacingText(message, maximumCharacters: 5_000)
        guard evidence.count <= 4 else { throw CoachLLMError.invalidResponse }
        try evidence.forEach { try validateUserFacingText($0, maximumCharacters: 500) }

        let workout = try decodeWorkout(dictionary["workout"])
        let intent = try decodeIntent(dictionary["intent"])

        switch kind {
        case .analysis:
            guard workout == nil, intent == nil else { throw CoachLLMError.invalidResponse }
        case .workoutProposal:
            guard workout != nil, intent == nil else { throw CoachLLMError.invalidResponse }
        case .deterministicIntent:
            guard workout == nil, intent != nil, evidence.isEmpty else {
                throw CoachLLMError.invalidResponse
            }
        }

        return CoachLLMResponse(
            kind: kind,
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            evidence: evidence.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            workout: workout,
            intent: intent
        )
    }

    private static func decodeWorkout(_ value: Any?) throws -> CoachLLMWorkoutProposal? {
        guard let value, !(value is NSNull) else { return nil }
        guard let dictionary = value as? [String: Any] else {
            throw CoachLLMError.invalidResponse
        }

        try requireExactKeys(
            dictionary,
            allowed: workoutKeys,
            required: ["sport", "focus", "dateISO", "targetMinutes", "goal"]
        )

        guard let sportRaw = dictionary["sport"] as? String,
              let sport = Sport(rawValue: sportRaw),
              let focusRaw = dictionary["focus"] as? String,
              let focus = CoachLLMWorkoutProposal.Focus(rawValue: focusRaw),
              let dateISO = dictionary["dateISO"] as? String,
              isISODate(dateISO),
              let target = integer(dictionary["targetMinutes"]),
              (10...180).contains(target),
              let goal = dictionary["goal"] as? String else {
            throw CoachLLMError.invalidResponse
        }

        try validateUserFacingText(goal, maximumCharacters: 300)

        return CoachLLMWorkoutProposal(
            sport: sport,
            focus: focus,
            dateISO: dateISO,
            targetMinutes: target,
            goal: goal.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func decodeIntent(_ value: Any?) throws -> CoachLLMDeterministicIntent? {
        guard let value, !(value is NSNull) else { return nil }
        guard let dictionary = value as? [String: Any] else {
            throw CoachLLMError.invalidResponse
        }

        try requireExactKeys(
            dictionary,
            allowed: intentKeys,
            required: ["kind", "sourceDateISO", "targetDateISO", "endDateISO", "maxMinutes", "easeReason"]
        )

        guard let kindRaw = dictionary["kind"] as? String,
              let kind = CoachLLMDeterministicIntent.Kind(rawValue: kindRaw) else {
            throw CoachLLMError.invalidResponse
        }

        let source = try optionalISODate(dictionary["sourceDateISO"])
        let target = try optionalISODate(dictionary["targetDateISO"])
        let end = try optionalISODate(dictionary["endDateISO"])
        let maxMinutes = try optionalInteger(dictionary["maxMinutes"])

        if let maxMinutes, !(10...240).contains(maxMinutes) {
            throw CoachLLMError.invalidResponse
        }

        let easeReason: CoachEaseReason?
        if dictionary["easeReason"] is NSNull || dictionary["easeReason"] == nil {
            easeReason = nil
        } else if let raw = dictionary["easeReason"] as? String,
                  let decoded = CoachEaseReason(rawValue: raw) {
            easeReason = decoded
        } else {
            throw CoachLLMError.invalidResponse
        }

        try validateIntentArguments(
            kind: kind,
            source: source,
            target: target,
            end: end,
            maxMinutes: maxMinutes
        )

        return CoachLLMDeterministicIntent(
            kind: kind,
            sourceDateISO: source,
            targetDateISO: target,
            endDateISO: end,
            maxMinutes: maxMinutes,
            easeReason: easeReason
        )
    }

    private static func validateIntentArguments(
        kind: CoachLLMDeterministicIntent.Kind,
        source: String?,
        target: String?,
        end: String?,
        maxMinutes: Int?
    ) throws {
        switch kind {
        case .moveSession:
            guard source != nil, target != nil else { throw CoachLLMError.invalidResponse }
        case .skipSession, .unavailable, .easeSession:
            guard source != nil || target != nil else { throw CoachLLMError.invalidResponse }
        case .unavailableRange:
            guard (source != nil || target != nil), end != nil else {
                throw CoachLLMError.invalidResponse
            }
        case .limitSession:
            guard (source != nil || target != nil), maxMinutes != nil else {
                throw CoachLLMError.invalidResponse
            }
        }
    }

    private static func validateUserFacingText(
        _ text: String,
        maximumCharacters: Int
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let codeFence = String(repeating: "`", count: 3)

        guard !trimmed.isEmpty,
              trimmed.count <= maximumCharacters,
              !trimmed.contains(codeFence),
              !trimmed.lowercased().contains("<script"),
              !trimmed.contains("BEGIN PRIVATE KEY"),
              !trimmed.contains("sk-") else {
            throw CoachLLMError.invalidResponse
        }

        let lowered = trimmed.lowercased()
        guard !forbiddenFragments.contains(where: lowered.contains) else {
            throw CoachLLMError.invalidResponse
        }
    }

    private static func requireExactKeys(
        _ dictionary: [String: Any],
        allowed: Set<String>,
        required: Set<String>
    ) throws {
        let keys = Set(dictionary.keys)
        guard keys.isSubset(of: allowed),
              required.isSubset(of: keys) else {
            throw CoachLLMError.invalidResponse
        }
    }

    private static func optionalISODate(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String, isISODate(string) else {
            throw CoachLLMError.invalidResponse
        }
        return string
    }

    private static func optionalInteger(_ value: Any?) throws -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        guard let decoded = integer(value) else { throw CoachLLMError.invalidResponse }
        return decoded
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double else { return nil }
        return Int(double)
    }

    private static func isISODate(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }
}
