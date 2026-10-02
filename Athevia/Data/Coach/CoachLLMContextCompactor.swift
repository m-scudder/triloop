import Foundation

struct CoachLLMConversationTurn: Codable, Equatable, Sendable {
    let role: CoachChatRole
    let text: String
}

enum CoachLLMContextCompactor {
    static let maximumConversationTurns = 4
    static let maximumConversationCharacters = 280

    static func conversation(
        from messages: [CoachChatMessage]
    ) -> [CoachLLMConversationTurn] {
        messages
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
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
