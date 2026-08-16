import Foundation

/// In-flight answers from the feedback sheet.
///
/// Kept as a plain value type rather than mutating a `WorkoutFeedback` directly
/// so dismissing the sheet cannot leave a half-filled model in the store, and so
/// the capture rules stay testable without SwiftUI or SwiftData.
struct FeedbackDraft: Equatable, Sendable {
    var rpe: Int
    var painScore: Int
    var painLocations: Set<PainLocation>
    var recoveryFeeling: RecoveryFeeling
    var notes: String

    /// Defaults describe an unremarkable easy session, which is the common case
    /// for a beginner plan and keeps the sheet to two taps.
    init(
        rpe: Int = 3,
        painScore: Int = 0,
        painLocations: Set<PainLocation> = [],
        recoveryFeeling: RecoveryFeeling = .good,
        notes: String = ""
    ) {
        self.rpe = rpe
        self.painScore = painScore
        self.painLocations = painLocations
        self.recoveryFeeling = recoveryFeeling
        self.notes = notes
    }

    var reportsPain: Bool { painScore > PainScale.minimum }

    /// Drops pain locations the athlete selected and then took back by
    /// returning pain to zero, and discards whitespace-only notes.
    func sanitized() -> FeedbackDraft {
        var copy = self
        copy.rpe = min(max(rpe, RPEScale.minimum), RPEScale.maximum)
        copy.painScore = min(max(painScore, PainScale.minimum), PainScale.maximum)
        copy.painLocations = copy.painScore == 0 ? [] : painLocations
        copy.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    func makeFeedback(createdAt: Date = .now) -> WorkoutFeedback {
        let clean = sanitized()
        return WorkoutFeedback(
            rpe: clean.rpe,
            painScore: clean.painScore,
            painLocations: clean.painLocations.sorted { $0.sortOrder < $1.sortOrder },
            recoveryFeeling: clean.recoveryFeeling,
            notes: clean.notes,
            createdAt: createdAt
        )
    }
}

extension PainLocation {
    /// Stable ordering for persisted arrays so equality checks are not
    /// dependent on `Set` iteration order.
    var sortOrder: Int {
        PainLocation.allCases.firstIndex(of: self) ?? 0
    }
}
