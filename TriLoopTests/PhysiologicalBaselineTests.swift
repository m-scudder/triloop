import Foundation
import Testing
@testable import TriLoop

@Suite("Physiological baselines")
struct PhysiologicalBaselineTests {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// Readings on consecutive days, ending yesterday.
    private func readings(_ values: [Double]) -> [RecoveryReading] {
        values.enumerated().map { index, value in
            RecoveryReading(
                date: now.addingTimeInterval(-Double(values.count - index) * 86_400),
                value: value
            )
        }
    }

    @Test("A short history produces a baseline once there are enough readings")
    func sevenDayBaseline() throws {
        let baseline = try #require(
            PhysiologicalBaselinePolicy.baseline(
                from: readings([50, 52, 51, 53]),
                window: .sevenDay,
                asOf: now
            ).value
        )
        #expect(baseline.readingCount == 4)
        #expect(abs(baseline.average - 51.5) < 0.0001)
        #expect(baseline.latest == 53)
    }

    @Test("Too few readings report insufficient history, not a guess")
    func insufficientHistory() {
        #expect(
            PhysiologicalBaselinePolicy.baseline(
                from: readings([50, 52]),
                window: .sevenDay,
                asOf: now
            ) == .insufficientHistory(found: 2, required: 4)
        )
    }

    @Test("The long window demands more than the short one")
    func longWindowNeedsMore() {
        let sparse = readings([50, 51, 52, 53, 54])
        #expect(PhysiologicalBaselinePolicy.baseline(from: sparse, window: .sevenDay, asOf: now).isAvailable)
        #expect(!PhysiologicalBaselinePolicy.baseline(from: sparse, window: .twentyEightDay, asOf: now).isAvailable)
    }

    @Test("Readings outside the window are excluded")
    func excludesOldReadings() throws {
        let old = (0..<10).map { index in
            RecoveryReading(date: now.addingTimeInterval(-Double(index + 20) * 86_400), value: 90)
        }
        let recent = readings([50, 50, 50, 50])

        let baseline = try #require(
            PhysiologicalBaselinePolicy.baseline(
                from: old + recent,
                window: .sevenDay,
                asOf: now
            ).value
        )
        // The 90s are three weeks old and must not distort a seven-day baseline.
        #expect(baseline.average == 50)
        #expect(baseline.readingCount == 4)
    }

    @Test("A reading above the recent range is reported as above")
    func standingAbove() throws {
        let baseline = try #require(
            PhysiologicalBaselinePolicy.baseline(
                from: readings([50, 50, 50, 62]),
                window: .sevenDay,
                asOf: now
            ).value
        )
        #expect(baseline.standing(tolerance: 3) == .above)
    }

    @Test("A reading close to the baseline is within range")
    func standingWithinRange() throws {
        let baseline = try #require(
            PhysiologicalBaselinePolicy.baseline(
                from: readings([50, 51, 50, 51]),
                window: .sevenDay,
                asOf: now
            ).value
        )
        #expect(baseline.standing(tolerance: 3) == .withinRange)
    }

    @Test("Deviation is expressed in the metric's own units")
    func deviation() throws {
        let baseline = try #require(
            PhysiologicalBaselinePolicy.baseline(
                from: readings([50, 50, 50, 56]),
                window: .sevenDay,
                asOf: now
            ).value
        )
        #expect(abs((baseline.deviation ?? 0) - 4.5) < 0.0001)
    }

    @Test("Language observes rather than diagnoses")
    func languageIsObservational() {
        let text = PhysiologicalBaselinePolicy.describe(
            .below,
            metric: "HRV",
            higherIsBetter: true
        )
        #expect(text == "HRV is below your recent range.")
        // §43 forbids the clinical register entirely.
        #expect(!text.lowercased().contains("overtrained"))
        #expect(!text.lowercased().contains("bad"))
    }

    @Test("No readings at all is insufficient history")
    func noReadings() {
        #expect(
            PhysiologicalBaselinePolicy.baseline(from: [], window: .sevenDay, asOf: now)
                == .insufficientHistory(found: 0, required: 4)
        )
    }
}
