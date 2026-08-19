import Foundation
import Testing
@testable import TriLoop

@Suite("Heart rate ceiling")
struct HeartRateCeilingTests {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func birthDate(yearsAgo years: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: -years, to: now) ?? now
    }

    @Test("Age gives the conventional predicted maximum")
    func ageBasedMaximum() {
        #expect(HeartRateCeiling.ageBased(birthDate: birthDate(yearsAgo: 40), asOf: now) == 180)
        #expect(HeartRateCeiling.ageBased(birthDate: birthDate(yearsAgo: 25), asOf: now) == 195)
    }

    @Test("Implausible ages produce no ceiling rather than a nonsense one")
    func implausibleAges() {
        #expect(HeartRateCeiling.ageBased(birthDate: birthDate(yearsAgo: 3), asOf: now) == nil)
        #expect(HeartRateCeiling.ageBased(birthDate: now, asOf: now) == nil)
    }

    @Test("A harder recorded effort beats the age prediction")
    func observedEffortWins() throws {
        let resolved = try #require(
            HeartRateCeiling.resolve(birthDate: birthDate(yearsAgo: 40), observedMaximum: 191, asOf: now)
        )
        // The formula is a population average; the athlete actually did 191.
        #expect(resolved.maximum == 191)
        #expect(resolved.source == .observedMaximum)
    }

    @Test("A lower observed effort does not drag the ceiling down")
    func easyHistoryDoesNotLowerTheCeiling() throws {
        // The beginner trap: never training hard must not make every session
        // look hard by shrinking the scale.
        let resolved = try #require(
            HeartRateCeiling.resolve(birthDate: birthDate(yearsAgo: 40), observedMaximum: 150, asOf: now)
        )
        #expect(resolved.maximum == 180)
        #expect(resolved.source == .ageBasedMaximum)
    }

    @Test("Observed effort is used when no birth date was given")
    func observedOnly() throws {
        let resolved = try #require(
            HeartRateCeiling.resolve(birthDate: nil, observedMaximum: 176, asOf: now)
        )
        #expect(resolved.source == .observedMaximum)
    }

    @Test("No evidence produces no ceiling")
    func noEvidence() {
        #expect(HeartRateCeiling.resolve(birthDate: nil, observedMaximum: nil, asOf: now) == nil)
    }
}

@Suite("Heart rate zones")
struct HeartRateZoneCalculatorTests {

    private let calculator = HeartRateZoneCalculator(maximumHeartRate: 180, source: .ageBasedMaximum)
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func readings(_ values: [Double], secondsApart: TimeInterval = 60) -> [HeartRateReading] {
        values.enumerated().map { index, bpm in
            HeartRateReading(
                date: start.addingTimeInterval(Double(index) * secondsApart),
                beatsPerMinute: bpm
            )
        }
    }

    @Test("Boundaries follow percentage of maximum")
    func boundaries() {
        let bounds = calculator.boundaries()
        #expect(bounds.count == 5)
        #expect(bounds[0].upper == 108)
        #expect(bounds[3].upper == 162)
        // The top zone is open-ended: there is no ceiling above maximum.
        #expect(bounds[4].upper == nil)
    }

    @Test("Zone 1 starts at zero so no beat goes unaccounted")
    func zoneOneStartsAtZero() {
        #expect(calculator.boundaries()[0].lower == 0)
        #expect(calculator.zone(for: 60) == 1)
    }

    @Test("Readings land in the expected zone")
    func zoneForReading() {
        #expect(calculator.zone(for: 100) == 1)
        #expect(calculator.zone(for: 115) == 2)
        #expect(calculator.zone(for: 140) == 3)
        #expect(calculator.zone(for: 155) == 4)
        #expect(calculator.zone(for: 175) == 5)
    }

    @Test("A boundary value falls in the higher zone")
    func boundaryGoesUp() {
        #expect(calculator.zone(for: 108) == 2)
        #expect(calculator.zone(for: 107) == 1)
    }

    @Test("Time in zone is measured from the gaps between readings")
    func timeInZone() throws {
        let breakdown = try #require(calculator.breakdown(from: readings([100, 100, 140, 140])))
        #expect(breakdown.zones[0].duration == 120)
        #expect(breakdown.zones[2].duration == 120)
        #expect(breakdown.totalDuration == 240)
    }

    @Test("Uneven sampling is respected rather than assumed")
    func unevenSampling() throws {
        let uneven = [
            HeartRateReading(date: start, beatsPerMinute: 100),
            HeartRateReading(date: start.addingTimeInterval(300), beatsPerMinute: 140),
            HeartRateReading(date: start.addingTimeInterval(360), beatsPerMinute: 140)
        ]
        let breakdown = try #require(calculator.breakdown(from: uneven))
        #expect(breakdown.zones[0].duration == 300)
    }

    @Test("Shares are proportions of the measured time")
    func shares() throws {
        let breakdown = try #require(calculator.breakdown(from: readings([100, 100, 100, 140])))
        #expect(abs(breakdown.share(of: breakdown.zones[0]) - 0.75) < 0.0001)
    }

    @Test("Too few readings produce nothing rather than an empty breakdown")
    func insufficientReadings() {
        #expect(calculator.breakdown(from: []) == nil)
        #expect(calculator.breakdown(from: readings([140])) == nil)
    }

    @Test("A zero maximum produces nothing rather than dividing by it")
    func zeroMaximum() {
        let broken = HeartRateZoneCalculator(maximumHeartRate: 0, source: .ageBasedMaximum)
        #expect(broken.breakdown(from: readings([100, 120])) == nil)
    }

    @Test("The breakdown records what set the ceiling")
    func sourceIsRetained() throws {
        let observed = HeartRateZoneCalculator(maximumHeartRate: 190, source: .observedMaximum)
        let breakdown = try #require(observed.breakdown(from: readings([100, 120])))
        #expect(breakdown.source == .observedMaximum)
    }

    @Test("Readings out of order are sorted before measuring")
    func unorderedReadings() throws {
        let shuffled = readings([100, 100, 140]).reversed()
        let breakdown = try #require(calculator.breakdown(from: Array(shuffled)))
        #expect(breakdown.totalDuration == 180)
    }
}
