import Foundation

enum CoachRequestScopeGuard {
    private static let forbiddenFragments = [
        "system prompt",
        "developer message",
        "hidden instruction",
        "ignore previous",
        "ignore all previous",
        "jailbreak",
        "developer mode",
        "source code",
        "github",
        "repository",
        "api key",
        "secret key",
        "service role",
        "service_role",
        "environment variable",
        "database schema",
        "database table",
        "sql",
        "swiftdata",
        "supabase",
        "openai key",
        "authentication token",
        "bearer token",
        "show internal",
        "dump context",
        "raw context",
        "hidden context"
    ]

    private static let trainingTerms = [
        "workout", "training", "run", "running", "ride", "cycling",
        "cycle", "bike", "swim", "swimming", "recovery", "rpe", "pace",
        "heart rate", "session", "reschedule workout", "skip workout",
        "training availability", "time off training", "fatigue", "tired",
        "poor sleep", "interval", "endurance", "effort", "5k", "10k",
        "half marathon", "marathon", "triathlon", "training history",
        "completed workout", "planned workout"
    ]

    private static let safeFollowUps: Set<String> = [
        "why",
        "why?",
        "how",
        "how?",
        "explain",
        "tell me more",
        "what changed",
        "what about tomorrow",
        "what about today",
        "and tomorrow",
        "and today"
    ]

    static func allows(
        _ request: String,
        recentMessages: [CoachChatMessage]
    ) -> Bool {
        let normalized = request
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty, normalized.count <= 1_200 else { return false }

        if forbiddenFragments.contains(where: normalized.contains) {
            return false
        }

        if trainingTerms.contains(where: normalized.contains) {
            return true
        }

        // Short follow-ups are allowed only inside an existing training
        // conversation; this supports natural multi-turn Coach use without
        // turning the endpoint into a general-purpose assistant.
        if !recentMessages.isEmpty,
           (safeFollowUps.contains(normalized) || normalized.count <= 24) {
            return true
        }

        return false
    }
}
