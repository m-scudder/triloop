import Foundation

enum AthleteEventStatus: String, Codable, CaseIterable, Sendable {
    case upcoming
    case completed
    case missed
    case cancelled
}

enum EventCompletionEvidenceSource: String, Codable, Sendable {
    case healthKitImport
    case atheviaWorkout
    case athleteConfirmation
}

struct AthleteEventState: Codable, Equatable, Sendable {
    var status: AthleteEventStatus
    var resolvedAt: Date?
    var completionEvidence: EventCompletionEvidenceSource?

    init(
        status: AthleteEventStatus = .upcoming,
        resolvedAt: Date? = nil,
        completionEvidence: EventCompletionEvidenceSource? = nil
    ) {
        self.status = status
        self.resolvedAt = resolvedAt
        self.completionEvidence = status == .completed ? completionEvidence : nil
    }

    static let upcoming = AthleteEventState()
}

struct EventRecoveryPolicy: Equatable, Sendable {
    func recoveryDays(for event: AthleteEventGoal) -> Int {
        switch event.distance?.kind {
        case .run5K, .swimming500M, .cycling20K, .triathlonSuperSprint:
            3
        case .run10K, .swimming1K, .cycling50K, .triathlonSprint:
            5
        case .runHalfMarathon, .swimming2K, .cycling100K, .triathlonOlympic:
            10
        case .runMarathon, .triathlon703:
            14
        case .runCustom, .swimmingCustom, .cyclingCustom, .triathlonCustom, .none:
            7
        }
    }

    func isRecovering(
        event: AthleteEventGoal,
        state: AthleteEventState,
        asOf date: Date,
        calendar: Calendar
    ) -> Bool {
        guard state.status == .completed else { return false }
        let completion = state.resolvedAt ?? event.eventDate
        guard let completion else { return false }
        let end = calendar.date(
            byAdding: .day,
            value: recoveryDays(for: event),
            to: calendar.startOfDay(for: completion)
        ) ?? completion
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: end)
    }

    func daysRemaining(
        event: AthleteEventGoal,
        state: AthleteEventState,
        asOf date: Date,
        calendar: Calendar
    ) -> Int? {
        guard state.status == .completed else { return nil }
        let completion = state.resolvedAt ?? event.eventDate
        guard let completion else { return nil }
        let end = calendar.date(
            byAdding: .day,
            value: recoveryDays(for: event),
            to: calendar.startOfDay(for: completion)
        ) ?? completion
        return max(
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: end)
            ).day ?? 0,
            0
        )
    }
}

extension AthleteEventState {
    var needsOutcomeResolution: Bool {
        status == .upcoming
    }
}
