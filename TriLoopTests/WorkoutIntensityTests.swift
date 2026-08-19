import Foundation
import Testing
@testable import TriLoop

@Suite("Workout intensity")
struct WorkoutIntensityTests {

    /// Durations in seconds for zones 1 through 5.
    private func zones(_ durations: [TimeInterval]) -> HeartRateZoneBreakdown {
        HeartRateZoneBreakdown(
            zones: durations.enumerated().map { index, duration in
                HeartRateZone(
                    number: index + 1,
                    lowerBoundBPM: Double(index) * 20,
                    upperBoundBPM: index == 4 ? nil : Double(index + 1) * 20,
                    duration: duration
                )
            },
            source: .ageBasedMaximum
        )
    }

    // MARK: - From zones

    @Test("A session spent low reads as easy")
    func easyFromZones() {
        #expect(WorkoutIntensityPolicy.intensity(from: zones([600, 1_200, 0, 0, 0])) == .easy)
    }

    @Test("Meaningful time at zone 3 makes it moderate")
    func moderateFromZones() {
        #expect(WorkoutIntensityPolicy.intensity(from: zones([600, 600, 600, 0, 0])) == .moderate)
    }

    @Test("A fifth of the session above zone 3 makes it hard")
    func hardFromZones() {
        #expect(WorkoutIntensityPolicy.intensity(from: zones([600, 600, 200, 300, 100])) == .hard)
    }

    @Test("A breakdown that measured nothing yields no reading")
    func emptyZonesYieldNothing() {
        // The trap: an all-zero breakdown must not read as easy.
        #expect(WorkoutIntensityPolicy.intensity(from: zones([0, 0, 0, 0, 0])) == nil)
    }

    // MARK: - From effort

    @Test("The effort scale maps to the three bands")
    func effortMapping() {
        #expect(WorkoutIntensityPolicy.intensity(fromRPE: 2) == .easy)
        #expect(WorkoutIntensityPolicy.intensity(fromRPE: 4) == .easy)
        #expect(WorkoutIntensityPolicy.intensity(fromRPE: 5) == .moderate)
        #expect(WorkoutIntensityPolicy.intensity(fromRPE: 6) == .moderate)
        #expect(WorkoutIntensityPolicy.intensity(fromRPE: 7) == .hard)
        #expect(WorkoutIntensityPolicy.intensity(fromRPE: 10) == .hard)
    }

    // MARK: - Combined

    @Test("No evidence is unavailable, not easy")
    func noEvidenceIsUnavailable() {
        let result = WorkoutIntensityPolicy.intensity(zones: nil, effort: EffortEvidence())
        #expect(result == .unavailable)
        // §33 states this outright: absence of evidence is not evidence of ease.
        #expect(result.value?.intensity != .easy)
    }

    @Test("A prescription alone is not evidence")
    func targetAloneIsNotEvidence() {
        let result = WorkoutIntensityPolicy.intensity(
            zones: nil,
            effort: EffortEvidence(targetRPE: 8)
        )
        #expect(result == .unavailable)
    }

    @Test("Heart rate alone is enough")
    func zonesAlone() throws {
        let result = WorkoutIntensityPolicy.intensity(
            zones: zones([600, 1_200, 0, 0, 0]),
            effort: EffortEvidence()
        )
        let reading = try #require(result.value)
        #expect(reading.intensity == .easy)
        #expect(reading.evidence == .heartRateZones)
    }

    @Test("Reported effort alone is enough")
    func effortAlone() throws {
        let reading = try #require(
            WorkoutIntensityPolicy.intensity(zones: nil, effort: EffortEvidence(reportedRPE: 8)).value
        )
        #expect(reading.intensity == .hard)
        #expect(reading.evidence == .reportedEffort)
    }

    @Test("Agreeing sources are recorded as hybrid")
    func agreementIsHybrid() throws {
        let reading = try #require(
            WorkoutIntensityPolicy.intensity(
                zones: zones([600, 1_200, 0, 0, 0]),
                effort: EffortEvidence(reportedRPE: 3)
            ).value
        )
        #expect(reading.intensity == .easy)
        #expect(reading.evidence == .hybrid)
    }

    @Test("Disagreement takes the harder reading and says so")
    func conflictTakesTheHarderReading() throws {
        // The conflicting-signals fixture: comfortable heart rate, high effort.
        let reading = try #require(
            WorkoutIntensityPolicy.intensity(
                zones: zones([600, 1_200, 0, 0, 0]),
                effort: EffortEvidence(reportedRPE: 8)
            ).value
        )
        #expect(reading.intensity == .hard)
        #expect(reading.evidence == .conflicting)
    }

    @Test("The athlete's own rating outranks Apple's estimate")
    func reportedEffortWinsOverApple() throws {
        let reading = try #require(
            WorkoutIntensityPolicy.intensity(
                zones: nil,
                effort: EffortEvidence(reportedRPE: 3, estimatedHealthKitEffort: 9)
            ).value
        )
        #expect(reading.intensity == .easy)
        #expect(reading.evidence == .reportedEffort)
    }

    @Test("Apple's score is used when the athlete reported nothing")
    func appleEffortIsFallback() throws {
        let reading = try #require(
            WorkoutIntensityPolicy.intensity(
                zones: nil,
                effort: EffortEvidence(estimatedHealthKitEffort: 8)
            ).value
        )
        #expect(reading.intensity == .hard)
        #expect(reading.evidence == .healthKitEffort)
    }

    @Test("The same inputs always give the same reading")
    func deterministic() {
        let zoneData = zones([600, 600, 200, 300, 100])
        let effort = EffortEvidence(reportedRPE: 4)

        let first = WorkoutIntensityPolicy.intensity(zones: zoneData, effort: effort)
        let second = WorkoutIntensityPolicy.intensity(zones: zoneData, effort: effort)
        #expect(first == second)
    }
}
