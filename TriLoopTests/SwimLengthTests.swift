import Foundation
import Testing

@testable import TriLoop

@Suite("Continuous swimming")
struct SwimLengthTests {

    private func lengths(_ gaps: [TimeInterval], meters: Double = 25) -> [SwimLength] {
        var start = Date(timeIntervalSince1970: 1_787_000_000)
        var result: [SwimLength] = []

        for gap in gaps {
            start = start.addingTimeInterval(gap)
            let end = start.addingTimeInterval(30)
            result.append(SwimLength(interval: DateInterval(start: start, end: end), meters: meters))
            start = end
        }
        return result
    }

    @Test("No lengths means no measurement")
    func emptyGivesNil() {
        #expect(HealthKitWorkoutImporter.longestContinuous(in: []) == nil)
    }

    @Test("Back-to-back lengths accumulate")
    func continuousLengthsAdd() {
        // Four lengths, only turn-length pauses between them.
        let swim = lengths([0, 2, 2, 2])

        #expect(HealthKitWorkoutImporter.longestContinuous(in: swim) == 100)
    }

    @Test("A rest breaks the run")
    func restResetsTheCount() {
        // Two lengths, a 40 second rest, then three more.
        let swim = lengths([0, 2, 40, 2, 2])

        #expect(HealthKitWorkoutImporter.longestContinuous(in: swim) == 75)
    }

    @Test("The longest block wins, not the last")
    func longestBlockIsKept() {
        let swim = lengths([0, 2, 2, 60, 2])

        #expect(HealthKitWorkoutImporter.longestContinuous(in: swim) == 75)
    }

    @Test("Every length rested means one length is the best")
    func allRestedGivesSingleLength() {
        let swim = lengths([0, 45, 45, 45])

        #expect(HealthKitWorkoutImporter.longestContinuous(in: swim) == 25)
    }
}
