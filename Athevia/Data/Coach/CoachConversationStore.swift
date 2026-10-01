import Foundation

enum CoachChatRole: String, Codable, Sendable {
    case athlete
    case coach
}

struct CoachChatMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: CoachChatRole
    let text: String
    let evidence: [String]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: CoachChatRole,
        text: String,
        evidence: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.evidence = Array(evidence.prefix(4))
        self.createdAt = createdAt
    }
}

struct CoachConversation: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [CoachChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "New conversation",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [CoachChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

/// Local conversation history is deliberately separate from SwiftData training
/// state. Chat persistence can evolve without forcing a training-store migration,
/// and deleting/signing out of an athlete scope can remove it independently.
struct CoachConversationStore {
    private let defaults: UserDefaults
    private let key: String
    private let maximumConversations: Int
    private let maximumMessagesPerConversation: Int

    init(
        athleteScopeID: String,
        defaults: UserDefaults = .standard,
        maximumConversations: Int = 30,
        maximumMessagesPerConversation: Int = 80
    ) {
        self.defaults = defaults
        self.key = "athevia.coach-conversations.v1.\(athleteScopeID)"
        self.maximumConversations = maximumConversations
        self.maximumMessagesPerConversation = maximumMessagesPerConversation
    }

    func conversations() -> [CoachConversation] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let decoded = try? decoder.decode([CoachConversation].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func create(at date: Date = .now) -> CoachConversation {
        let conversation = CoachConversation(createdAt: date, updatedAt: date)
        var all = conversations()
        all.insert(conversation, at: 0)
        save(all)
        return conversation
    }

    func saveConversation(_ conversation: CoachConversation) {
        var value = conversation
        if value.messages.count > maximumMessagesPerConversation {
            value.messages.removeFirst(value.messages.count - maximumMessagesPerConversation)
        }

        var all = conversations()
        all.removeAll { $0.id == value.id }
        all.insert(value, at: 0)
        if all.count > maximumConversations {
            all.removeLast(all.count - maximumConversations)
        }
        save(all)
    }

    func delete(_ conversationID: UUID) {
        var all = conversations()
        all.removeAll { $0.id == conversationID }
        save(all)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func save(_ conversations: [CoachConversation]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(conversations) else { return }
        defaults.set(data, forKey: key)
    }
}

enum CoachConversationTitle {
    static func from(firstRequest: String) -> String {
        let compact = firstRequest
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !compact.isEmpty else { return "New conversation" }
        let limit = 42
        return compact.count <= limit
            ? compact
            : String(compact.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
