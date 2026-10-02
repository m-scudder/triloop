import Foundation

struct CoachLLMConversationTurn: Codable, Equatable, Sendable {
    let role: CoachChatRole
    let text: String
}

enum CoachLLMContextCompactor {
    static let maximumConversationTurns = 4
    static let maximumConversationCharacters = 280

    static func conversation(
        from messages: [CoachChatMessage],
        excludingCurrentRequest request: String? = nil
    ) -> [CoachLLMConversationTurn] {
        var candidates = messages
        if let request,
           let last = candidates.last,
           last.role == .athlete,
           normalize(last.text) == normalize(request) {
            candidates.removeLast()
        }

        return candidates
            .suffix(maximumConversationTurns)
            .map {
                CoachLLMConversationTurn(
                    role: $0.role,
                    text: compact($0.text, limit: maximumConversationCharacters)
                )
            }
    }

    static func historyWindowDays(for request: String) -> Int {
        let text = request.lowercased()
        if text.contains("month")
            || text.contains("trend")
            || text.contains("progress")
            || text.contains("history")
            || text.contains("recent training")
            || text.contains("last few weeks") {
            return 28
        }
        return 14
    }

    static func maximumWorkoutRecords(for request: String) -> Int {
        historyWindowDays(for: request) > 14 ? 16 : 8
    }

    static func compact(_ value: String, limit: Int) -> String {
        let normalized = normalize(value)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
