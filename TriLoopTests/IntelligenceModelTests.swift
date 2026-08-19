import Foundation
import Testing
@testable import TriLoop

@Suite("Intelligence value availability")
struct IntelligenceValueTests {

    @Test("A recorded value is available")
    func recordedValueIsAvailable() {
        let value = IntelligenceValue(142.0)
        #expect(value == .available(142.0))
        #expect(value.isAvailable)
        #expect(value.value == 142.0)
    }

    @Test("A missing value is unavailable rather than zero")
    func missingValueIsNotZero() {
        let value = IntelligenceValue(Double?.none)
        #expect(value == .unavailable)
        #expect(value.value == nil)
        // The point of the type: nothing can mistake absence for a reading.
        #expect(value.value ?? 0 == 0)
        #expect(!value.isAvailable)
    }

    @Test("Mapping preserves the reason a value is absent")
    func mappingPreservesAbsence() {
        let insufficient = IntelligenceValue<Double>.insufficientHistory(found: 2, required: 4)
        #expect(insufficient.map { $0 * 2 } == .insufficientHistory(found: 2, required: 4))

        let failed = IntelligenceValue<Double>.queryFailure
        #expect(failed.map { $0 * 2 } == .queryFailure)
    }

    @Test("Mapping transforms an available value")
    func mappingTransformsValue() {
        #expect(IntelligenceValue(21.0).map { $0 * 2 } == .available(42.0))
    }
}

@Suite("Minimum history policy")
struct MinimumHistoryPolicyTests {

    @Test("Too few readings report what is missing instead of a baseline")
    func tooFewReadings() {
        let result = MinimumHistoryPolicy.value(readingCount: 2, window: .sevenDay) { 55.0 }
        #expect(result == .insufficientHistory(found: 2, required: 4))
    }

    @Test("Enough readings produce a baseline")
    func enoughReadings() {
        let result = MinimumHistoryPolicy.value(readingCount: 4, window: .sevenDay) { 55.0 }
        #expect(result == .available(55.0))
    }

    @Test("The longer window demands more readings")
    func longerWindowDemandsMore() {
        #expect(MinimumHistoryPolicy.hasEnough(readingCount: 10, for: .sevenDay))
        #expect(!MinimumHistoryPolicy.hasEnough(readingCount: 10, for: .twentyEightDay))
    }

    @Test("The baseline is not computed when history is short")
    func computeIsNotCalledWhenShort() {
        var computed = false
        _ = MinimumHistoryPolicy.value(readingCount: 1, window: .twentyEightDay) {
            computed = true
            return 0.0
        }
        #expect(!computed)
    }
}

@Suite("Heart rate zones")
struct HeartRateZoneTests {

    private func breakdown() -> HeartRateZoneBreakdown {
        HeartRateZoneBreakdown(
            zones: [
                HeartRateZone(number: 1, lowerBoundBPM: 90, upperBoundBPM: 110, duration: 600),
                HeartRateZone(number: 2, lowerBoundBPM: 110, upperBoundBPM: 130, duration: 1_200),
                HeartRateZone(number: 3, lowerBoundBPM: 130, upperBoundBPM: 150, duration: 200),
                HeartRateZone(number: 4, lowerBoundBPM: 150, upperBoundBPM: 170, duration: 0),
                HeartRateZone(number: 5, lowerBoundBPM: 170, upperBoundBPM: nil, duration: 0)
            ],
            source: .observedMaximum
        )
    }

    @Test("Total duration is the sum of the zones")
    func totalDuration() {
        #expect(breakdown().totalDuration == 2_000)
    }

    @Test("Shares are derived from duration and sum to one")
    func sharesSumToOne() {
        let zones = breakdown()
        #expect(zones.share(of: zones.zones[1]) == 0.6)

        let total = zones.zones.reduce(0.0) { $0 + zones.share(of: $1) }
        #expect(abs(total - 1.0) < 0.0001)
    }

    @Test("An empty session divides by zero safely")
    func emptySessionHasNoShare() {
        let empty = HeartRateZoneBreakdown(
            zones: [HeartRateZone(number: 1, lowerBoundBPM: 90, upperBoundBPM: 110, duration: 0)],
            source: .ageBasedMaximum
        )
        #expect(empty.totalDuration == 0)
        #expect(empty.share(of: empty.zones[0]) == 0)
    }
}

@Suite("Effort evidence")
struct EffortEvidenceTests {

    @Test("A prescription alone is not evidence of what happened")
    func targetIsNotEvidence() {
        // A target says what was asked for, not what the athlete did.
        #expect(!EffortEvidence(targetRPE: 4).hasAnyEvidence)
    }

    @Test("Any reported or measured effort counts as evidence")
    func reportedEffortCounts() {
        #expect(EffortEvidence(reportedRPE: 6).hasAnyEvidence)
        #expect(EffortEvidence(healthKitEffort: 7).hasAnyEvidence)
        #expect(EffortEvidence(estimatedHealthKitEffort: 5).hasAnyEvidence)
    }

    @Test("Apple's estimate is kept apart from the athlete's own rating")
    func sourcesStaySeparate() {
        let evidence = EffortEvidence(reportedRPE: 3, estimatedHealthKitEffort: 8)
        // Disagreement has to survive: §33 reports conflicting evidence.
        #expect(evidence.reportedRPE == 3)
        #expect(evidence.estimatedHealthKitEffort == 8)
    }
}
