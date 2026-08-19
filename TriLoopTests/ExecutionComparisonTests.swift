import Foundation
import Testing
@testable import TriLoop

@Suite("Planned versus actual")
struct ExecutionComparisonTests {

    private let thirtyMinutes: TimeInterval = 1_800

    // MARK: - Duration

    @Test("Finishing close to the prescription is within target")
    func closeEnoughIsWithinTarget() {
        #expect(ExecutionComparison.durationAdherence(planned: thirtyMinutes, actual: 1_800) == .withinTarget)
        #expect(ExecutionComparison.durationAdherence(planned: thirtyMinutes, actual: 1_920) == .withinTarget)
        #expect(ExecutionComparison.durationAdherence(planned: thirtyMinutes, actual: 1_680) == .withinTarget)
    }

    @Test("Going noticeably longer is above target")
    func longerIsAboveTarget() {
        #expect(ExecutionComparison.durationAdherence(planned: thirtyMinutes, actual: 2_400) == .aboveTarget)
    }

    @Test("Falling somewhat short is below target")
    func shorterIsBelowTarget() {
        #expect(ExecutionComparison.durationAdherence(planned: thirtyMinutes, actual: 1_400) == .belowTarget)
    }

    @Test("Stopping less than halfway is incomplete, not merely short")
    func farShortIsIncomplete() {
        #expect(ExecutionComparison.durationAdherence(planned: thirtyMinutes, actual: 600) == .incomplete)
    }

    @Test("Short sessions get a floor so small absolute gaps do not count")
    func toleranceFloorProtectsShortSessions() {
        // 10% of ten minutes is a minute, which is noise. The two-minute floor
        // keeps a 9-minute swim inside a 10-minute prescription.
        #expect(ExecutionComparison.durationAdherence(planned: 600, actual: 540) == .withinTarget)
        #expect(ExecutionComparison.durationAdherence(planned: 600, actual: 420) == .belowTarget)
    }

    @Test("No prescription or no recording means no duration verdict")
    func missingDurationEvidence() {
        #expect(ExecutionComparison.durationAdherence(planned: nil, actual: 1_800) == nil)
        #expect(ExecutionComparison.durationAdherence(planned: thirtyMinutes, actual: nil) == nil)
        #expect(ExecutionComparison.durationAdherence(planned: 0, actual: 1_800) == nil)
    }

    // MARK: - Effort

    @Test("Effort inside the prescribed range is within target")
    func effortWithinRange() {
        #expect(ExecutionComparison.effortAdherence(target: RPERange(3, 4), reported: 3) == .withinTarget)
        #expect(ExecutionComparison.effortAdherence(target: RPERange(3, 4), reported: 4) == .withinTarget)
    }

    @Test("Effort outside the range is reported in the direction it went")
    func effortOutsideRange() {
        #expect(ExecutionComparison.effortAdherence(target: RPERange(3, 4), reported: 6) == .aboveTarget)
        #expect(ExecutionComparison.effortAdherence(target: RPERange(3, 4), reported: 2) == .belowTarget)
    }

    @Test("No target or no report means no effort verdict")
    func missingEffortEvidence() {
        #expect(ExecutionComparison.effortAdherence(target: nil, reported: 5) == nil)
        #expect(ExecutionComparison.effortAdherence(target: RPERange(3, 4), reported: nil) == nil)
    }

    // MARK: - Combined

    private func compare(
        planned: TimeInterval? = 1_800,
        actual: TimeInterval? = 1_800,
        target: RPERange? = RPERange(3, 4),
        reported: Int? = 3,
        completion: ExecutionComparison.Completion = .recorded
    ) -> ExecutionComparison.Outcome? {
        ExecutionComparison.compare(
            plannedSeconds: planned,
            actualSeconds: actual,
            targetRPE: target,
            reportedRPE: reported,
            completion: completion,
            tolerance: .standard
        )
    }

    @Test("A session done as prescribed is within target overall")
    func matchingSession() throws {
        let outcome = try #require(compare())
        #expect(outcome.duration == .withinTarget)
        #expect(outcome.effort == .withinTarget)
        #expect(outcome.overall == .withinTarget)
    }

    @Test("Effort above target outranks a duration that was fine")
    func hardEffortWins() throws {
        // The safety-relevant signal: the athlete found an easy session hard.
        let outcome = try #require(compare(reported: 8))
        #expect(outcome.duration == .withinTarget)
        #expect(outcome.effort == .aboveTarget)
        #expect(outcome.overall == .aboveTarget)
    }

    @Test("Going harder outranks going easier when the two disagree")
    func harderOutranksEasier() throws {
        let outcome = try #require(compare(actual: 1_400, reported: 8))
        #expect(outcome.duration == .belowTarget)
        #expect(outcome.overall == .aboveTarget)
    }

    @Test("An incomplete session outranks any effort reading")
    func incompleteWins() throws {
        let outcome = try #require(compare(actual: 400, reported: 8))
        #expect(outcome.overall == .incomplete)
    }

    @Test("Skipped and missed are stated as themselves")
    func skippedAndMissed() throws {
        #expect(try #require(compare(completion: .skipped)).overall == .skipped)
        #expect(try #require(compare(completion: .missed)).overall == .missed)
    }

    @Test("A skipped session ignores whatever else was recorded")
    func skippedIgnoresOtherEvidence() throws {
        let outcome = try #require(compare(actual: 1_800, reported: 3, completion: .skipped))
        #expect(outcome.duration == nil)
        #expect(outcome.overall == .skipped)
    }

    @Test("A session still in the future has no verdict at all")
    func futureSessionHasNoVerdict() {
        #expect(compare(completion: .notYetDue) == nil)
    }

    @Test("A completed session with nothing to compare is not a failure")
    func noEvidenceIsStillCompleted() throws {
        let outcome = try #require(compare(planned: nil, actual: nil, target: nil, reported: nil))
        #expect(outcome.duration == nil)
        #expect(outcome.effort == nil)
        #expect(outcome.overall == .withinTarget)
    }
}
