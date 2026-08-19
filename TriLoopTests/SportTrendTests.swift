import Foundation
import Testing
@testable import TriLoop

@Suite("Trend analysis")
struct TrendAnalysisTests {

    private let anchor = Date(timeIntervalSince1970: 1_760_000_000)

    private func point(week: Int, value: Double) -> TrendPoint {
        TrendPoint(
            weekStart: anchor.addingTimeInterval(Double(week) * 7 * 86_400),
            value: value,
            sampleCount: 3
        )
    }

    @Test("Fewer than three weeks is insufficient history, not a trend")
    func needsThreeWeeks() {
        // Two points make a line; one good week would otherwise read as progress.
        #expect(
            TrendAnalysis.trend(from: [point(week: 0, value: 10), point(week: 1, value: 20)])
                == .insufficientHistory(found: 2, required: 3)
        )
    }

    @Test("A consistent increase is rising")
    func rising() throws {
        let trend = try #require(
            TrendAnalysis.trend(from: [
                point(week: 0, value: 100),
                point(week: 1, value: 110),
                point(week: 2, value: 120),
                point(week: 3, value: 130)
            ]).value
        )
        #expect(trend.direction == .rising)
        #expect(trend.change == 30)
    }

    @Test("Small movement is steady rather than progress")
    func steady() throws {
        let trend = try #require(
            TrendAnalysis.trend(from: [
                point(week: 0, value: 100),
                point(week: 1, value: 101),
                point(week: 2, value: 99),
                point(week: 3, value: 100)
            ]).value
        )
        #expect(trend.direction == .steady)
    }

    @Test("A single unusual week does not decide the direction")
    func resistsOneOddWeek() throws {
        // Halves are compared rather than endpoints, so the spike is diluted.
        let trend = try #require(
            TrendAnalysis.trend(from: [
                point(week: 0, value: 100),
                point(week: 1, value: 100),
                point(week: 2, value: 100),
                point(week: 3, value: 104)
            ]).value
        )
        #expect(trend.direction == .steady)
    }

    @Test("A consistent decrease is falling")
    func falling() throws {
        let trend = try #require(
            TrendAnalysis.trend(from: [
                point(week: 0, value: 400),
                point(week: 1, value: 380),
                point(week: 2, value: 340),
                point(week: 3, value: 320)
            ]).value
        )
        #expect(trend.direction == .falling)
    }

    @Test("Pace is weighted by distance, not averaged per session")
    func paceIsDistanceWeighted() throws {
        let sessions = [
            LoadedSession(date: anchor, sport: .running, durationSeconds: 600, distanceMeters: 2_000),
            LoadedSession(date: anchor, sport: .running, durationSeconds: 3_000, distanceMeters: 10_000)
        ]
        // Both ran at 300 s/km, so the weighted result must be exactly that
        // rather than anything the session count could distort.
        #expect(TrendAnalysis.averagePace(sessions) == 300)
    }

    @Test("Weeks are grouped from the anchor, not the locale's first weekday")
    func weeksGroupFromAnchor() {
        let sessions = (0..<14).map { day in
            LoadedSession(
                date: anchor.addingTimeInterval(Double(day) * 86_400),
                sport: .running,
                durationSeconds: 1_800
            )
        }
        let points = TrendAnalysis.weeklyValues(sessions, anchoredTo: anchor) {
            TrendAnalysis.totalDuration($0)
        }
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.sampleCount == 7 })
    }
}

@Suite("Running trends")
struct RunningTrendTests {

    private let anchor = Date(timeIntervalSince1970: 1_760_000_000)

    private func run(
        week: Int,
        day: Int = 0,
        minutes: Double,
        kilometres: Double,
        heartRate: Double? = nil,
        intensity: WorkoutIntensity = .easy,
        power: Double? = nil
    ) -> LoadedSession {
        LoadedSession(
            date: anchor.addingTimeInterval(Double(week * 7 + day) * 86_400),
            sport: .running,
            durationSeconds: minutes * 60,
            intensity: intensity,
            distanceMeters: kilometres * 1_000,
            averageHeartRate: heartRate,
            metrics: RecordedMetrics(averageRunningPower: power)
        )
    }

    @Test("Weekly distance accumulates per week")
    func weeklyDistance() throws {
        let trend = try #require(
            RunningTrends.weeklyDistance([
                run(week: 0, minutes: 30, kilometres: 5),
                run(week: 0, day: 3, minutes: 30, kilometres: 5),
                run(week: 1, minutes: 36, kilometres: 6),
                run(week: 2, minutes: 42, kilometres: 7)
            ], anchoredTo: anchor).value
        )
        #expect(trend.points.first?.value == 10_000)
        #expect(trend.direction == .falling)
    }

    @Test("Sessions from other sports are ignored")
    func ignoresOtherSports() {
        let sessions = [
            LoadedSession(date: anchor, sport: .cycling, durationSeconds: 3_600, distanceMeters: 20_000)
        ]
        #expect(RunningTrends.weeklyDistance(sessions, anchoredTo: anchor) == .unavailable)
    }

    @Test("Power appears only when the hardware recorded it")
    func powerRequiresHardware() {
        let withoutPower = [
            run(week: 0, minutes: 30, kilometres: 5),
            run(week: 1, minutes: 30, kilometres: 5),
            run(week: 2, minutes: 30, kilometres: 5)
        ]
        #expect(!RunningTrends.power(withoutPower, anchoredTo: anchor).isAvailable)

        let withPower = [
            run(week: 0, minutes: 30, kilometres: 5, power: 240),
            run(week: 1, minutes: 30, kilometres: 5, power: 245),
            run(week: 2, minutes: 30, kilometres: 5, power: 250)
        ]
        #expect(RunningTrends.power(withPower, anchoredTo: anchor).isAvailable)
    }

    // MARK: - Similar runs

    @Test("Comparable easy runs are matched and compared")
    func similarEasyRuns() throws {
        let comparison = try #require(
            RunningTrends.similarEasyRuns([
                run(week: 0, minutes: 30, kilometres: 4.1, heartRate: 151),
                run(week: 4, minutes: 30, kilometres: 4.2, heartRate: 146)
            ])
        )
        #expect((comparison.paceChange ?? 0) < 0)
        #expect((comparison.heartRateChange ?? 0) < 0)
    }

    @Test("Runs of very different length are not compared")
    func rejectsDissimilarDurations() {
        // A 10-minute sprint against a 90-minute long run would show a pace
        // collapse that means nothing.
        #expect(
            RunningTrends.similarEasyRuns([
                run(week: 0, minutes: 10, kilometres: 2, heartRate: 150),
                run(week: 4, minutes: 90, kilometres: 12, heartRate: 150)
            ]) == nil
        )
    }

    @Test("Hard sessions are not compared with easy ones")
    func ignoresHardSessions() {
        #expect(
            RunningTrends.similarEasyRuns([
                run(week: 0, minutes: 30, kilometres: 4, heartRate: 150, intensity: .hard),
                run(week: 4, minutes: 30, kilometres: 4, heartRate: 150, intensity: .hard)
            ]) == nil
        )
    }

    @Test("The summary claims only what was observed")
    func summaryAvoidsFitnessClaims() throws {
        let comparison = try #require(
            RunningTrends.similarEasyRuns([
                run(week: 0, minutes: 30, kilometres: 4.0, heartRate: 150),
                run(week: 4, minutes: 30, kilometres: 4.3, heartRate: 149)
            ])
        )
        let summary = try #require(comparison.summary)
        #expect(summary.contains("faster at a similar heart rate"))
        // §44 rules this out explicitly.
        #expect(!summary.contains("%"))
        #expect(!summary.lowercased().contains("fitness"))
    }

    @Test("One run is not a comparison")
    func singleRunIsNotComparable() {
        #expect(RunningTrends.similarEasyRuns([run(week: 0, minutes: 30, kilometres: 5, heartRate: 150)]) == nil)
    }
}

@Suite("Swimming trends")
struct SwimmingTrendTests {

    private let anchor = Date(timeIntervalSince1970: 1_760_000_000)

    private func swim(week: Int, metres: Double, minutes: Double, longest: Double? = nil) -> LoadedSession {
        LoadedSession(
            date: anchor.addingTimeInterval(Double(week * 7) * 86_400),
            sport: .swimming,
            durationSeconds: minutes * 60,
            distanceMeters: metres,
            longestContinuousSwimMeters: longest
        )
    }

    @Test("Longest continuous swim tracks the beginner progression")
    func longestContinuous() throws {
        let trend = try #require(
            SwimmingTrends.longestContinuous([
                swim(week: 0, metres: 300, minutes: 30, longest: 25),
                swim(week: 1, metres: 350, minutes: 30, longest: 50),
                swim(week: 2, metres: 400, minutes: 30, longest: 75),
                swim(week: 3, metres: 450, minutes: 30, longest: 100)
            ], anchoredTo: anchor).value
        )
        #expect(trend.points.map(\.value) == [25, 50, 75, 100])
        #expect(trend.direction == .rising)
    }

    @Test("Elapsed pace is named for what it measures")
    func elapsedPace() throws {
        let trend = try #require(
            SwimmingTrends.elapsedPace([
                swim(week: 0, metres: 1_000, minutes: 30),
                swim(week: 1, metres: 1_000, minutes: 29),
                swim(week: 2, metres: 1_000, minutes: 28)
            ], anchoredTo: anchor).value
        )
        // 30 minutes for 1000 m is 180 s per 100 m, rests included.
        #expect(trend.points.first?.value == 180)
        #expect(trend.direction == .falling)
    }

    @Test("Swims without lap data still report volume")
    func volumeWithoutLaps() {
        #expect(
            SwimmingTrends.weeklyVolume([
                swim(week: 0, metres: 800, minutes: 25),
                swim(week: 1, metres: 900, minutes: 25),
                swim(week: 2, metres: 1_000, minutes: 25)
            ], anchoredTo: anchor).isAvailable
        )
    }
}

@Suite("Cycling trends")
struct CyclingTrendTests {

    private let anchor = Date(timeIntervalSince1970: 1_760_000_000)

    private func ride(
        week: Int,
        minutes: Double,
        kilometres: Double,
        cadence: Double? = nil,
        power: Double? = nil
    ) -> LoadedSession {
        LoadedSession(
            date: anchor.addingTimeInterval(Double(week * 7) * 86_400),
            sport: .cycling,
            durationSeconds: minutes * 60,
            distanceMeters: kilometres * 1_000,
            metrics: RecordedMetrics(averageCyclingCadence: cadence, averageCyclingPower: power)
        )
    }

    @Test("Speed is derived from the week's total distance and time")
    func speed() throws {
        let trend = try #require(
            CyclingTrends.speed([
                ride(week: 0, minutes: 60, kilometres: 24),
                ride(week: 1, minutes: 60, kilometres: 25),
                ride(week: 2, minutes: 60, kilometres: 26)
            ], anchoredTo: anchor).value
        )
        #expect(abs((trend.points.first?.value ?? 0) - 6.667) < 0.01)
        #expect(trend.direction == .rising)
    }

    @Test("Power is unavailable without a meter")
    func powerNeedsMeter() {
        let rides = [
            ride(week: 0, minutes: 60, kilometres: 24),
            ride(week: 1, minutes: 60, kilometres: 24),
            ride(week: 2, minutes: 60, kilometres: 24)
        ]
        // §46: the advanced section disappears rather than showing zero watts.
        #expect(!CyclingTrends.power(rides, anchoredTo: anchor).isAvailable)
        #expect(!CyclingTrends.cadence(rides, anchoredTo: anchor).isAvailable)
    }

    @Test("Cadence appears when the bike computer recorded it")
    func cadenceWhenAvailable() throws {
        let trend = try #require(
            CyclingTrends.cadence([
                ride(week: 0, minutes: 60, kilometres: 24, cadence: 80),
                ride(week: 1, minutes: 60, kilometres: 24, cadence: 84),
                ride(week: 2, minutes: 60, kilometres: 24, cadence: 88)
            ], anchoredTo: anchor).value
        )
        #expect(trend.points.map(\.value) == [80, 84, 88])
    }
}
