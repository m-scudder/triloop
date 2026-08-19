import Foundation
import Testing
@testable import TriLoop

@Suite("Session load")
struct SessionLoadTests {

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

    @Test("Load from effort is duration multiplied by how hard it felt")
    func effortLoad() throws {
        let load = try #require(
            SessionLoadPolicy.effortLoad(
                durationSeconds: 1_800,
                effort: EffortEvidence(reportedRPE: 4)
            )
        )
        #expect(load.value == 120)
        #expect(load.provenance == .reportedEffort)
    }

    @Test("Load from zones weights each minute by its zone")
    func zoneLoad() throws {
        // Twenty minutes in zone 2 (weight 4) plus ten in zone 4 (weight 8).
        let value = try #require(SessionLoadPolicy.zoneLoad(zones([0, 1_200, 0, 600, 0])))
        #expect(value == 160)
    }

    @Test("Zone weight is capped so the top zone does not run away")
    func zoneWeightCap() {
        #expect(SessionLoadPolicy.weight(forZone: 1) == 2)
        #expect(SessionLoadPolicy.weight(forZone: 5) == 10)
    }

    @Test("An unmeasured session has no load rather than a load of zero")
    func noEvidenceIsUnavailable() {
        let result = SessionLoadPolicy.load(
            durationSeconds: 1_800,
            zones: nil,
            effort: EffortEvidence()
        )
        #expect(result == .unavailable)
        // §35 states this: a zero would drag down every average it entered.
        #expect(result.value?.value != 0)
    }

    @Test("A session with no duration and no zones has no load")
    func noDurationIsUnavailable() {
        #expect(
            SessionLoadPolicy.load(
                durationSeconds: nil,
                zones: nil,
                effort: EffortEvidence(reportedRPE: 5)
            ) == .unavailable
        )
    }

    @Test("Both sources together are averaged and recorded as hybrid")
    func hybridLoad() throws {
        let load = try #require(
            SessionLoadPolicy.load(
                durationSeconds: 1_800,
                zones: zones([0, 1_800, 0, 0, 0]),
                effort: EffortEvidence(reportedRPE: 4)
            ).value
        )
        // Zones give 30 × 4 = 120, effort gives 30 × 4 = 120.
        #expect(load.value == 120)
        #expect(load.provenance == .hybrid)
    }

    @Test("Heart rate alone is recorded as such")
    func heartRateProvenance() throws {
        let load = try #require(
            SessionLoadPolicy.load(
                durationSeconds: 1_800,
                zones: zones([1_800, 0, 0, 0, 0]),
                effort: EffortEvidence()
            ).value
        )
        #expect(load.provenance == .heartRate)
    }

    @Test("The athlete's rating outranks Apple's estimate")
    func reportedEffortWins() throws {
        let load = try #require(
            SessionLoadPolicy.effortLoad(
                durationSeconds: 600,
                effort: EffortEvidence(reportedRPE: 2, estimatedHealthKitEffort: 9)
            )
        )
        #expect(load.value == 20)
        #expect(load.provenance == .reportedEffort)
    }

    @Test("A harder session of the same length carries more load")
    func harderMeansMoreLoad() throws {
        let easy = try #require(SessionLoadPolicy.effortLoad(durationSeconds: 1_800, effort: EffortEvidence(reportedRPE: 3)))
        let hard = try #require(SessionLoadPolicy.effortLoad(durationSeconds: 1_800, effort: EffortEvidence(reportedRPE: 8)))
        #expect(hard.value > easy.value)
    }

    @Test("A longer session at the same effort carries more load")
    func longerMeansMoreLoad() throws {
        let short = try #require(SessionLoadPolicy.effortLoad(durationSeconds: 900, effort: EffortEvidence(reportedRPE: 5)))
        let long = try #require(SessionLoadPolicy.effortLoad(durationSeconds: 2_700, effort: EffortEvidence(reportedRPE: 5)))
        #expect(long.value == short.value * 3)
    }

    @Test("An empty zone breakdown contributes nothing")
    func emptyZonesContributeNothing() {
        #expect(SessionLoadPolicy.zoneLoad(zones([0, 0, 0, 0, 0])) == nil)
    }
}
