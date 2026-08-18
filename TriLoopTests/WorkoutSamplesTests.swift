import Foundation
import Testing

@testable import TriLoop

@Suite("Workout samples")
struct WorkoutSamplesTests {

    private func point(_ minute: Int, _ value: Double) -> SamplePoint {
        SamplePoint(
            date: Date(timeIntervalSince1970: 1_787_000_000 + Double(minute) * 60),
            value: value
        )
    }

    @Test("Empty samples are reported as empty")
    func emptySamplesAreEmpty() {
        #expect(WorkoutSamples().isEmpty)
        #expect(WorkoutSamples().averageHeartRate == nil)
        #expect(WorkoutSamples().peakHeartRate == nil)
    }

    @Test("Heart rate is averaged and peaked across the session")
    func heartRateIsSummarised() {
        let samples = WorkoutSamples(
            heartRate: [point(0, 120), point(1, 140), point(2, 160)]
        )

        #expect(samples.isEmpty == false)
        #expect(samples.averageHeartRate == 140)
        #expect(samples.peakHeartRate == 160)
    }

    @Test("Swim pace is expressed per hundred metres")
    func swimPaceIsPerHundred() {
        let length = SwimLengthPoint(index: 1, start: .now, seconds: 30, meters: 25, followedRest: false)

        #expect(length.pacePer100m == 120)
    }

    @Test("A length with no distance has no pace rather than a divide by zero")
    func zeroDistanceHasNoPace() {
        let length = SwimLengthPoint(index: 1, start: .now, seconds: 30, meters: 0, followedRest: false)

        #expect(length.pacePer100m == 0)
    }

    @Test("An open-water swim reports pace from the distance series")
    func openWaterSwimStillHasPace() {
        let start = Date(timeIntervalSince1970: 1_787_000_000)
        // 30 m a minute for ten minutes: 300 m, so 3:20 per 100 m.
        let points = (0..<10).map {
            SamplePoint(date: start.addingTimeInterval(Double($0) * 60), value: 30)
        }

        let metrics = WorkoutMetric.all(
            for: .swimming,
            samples: WorkoutSamples(distancePerMinute: points)
        )

        #expect(metrics.map(\.kind) == [.swimPace])
        #expect(metrics.first?.headline == "3:20")
        #expect(metrics.first?.lengths.isEmpty == true)
    }

    @Test("A pool swim prefers lengths over the distance series")
    func poolSwimPrefersLengths() {
        let start = Date(timeIntervalSince1970: 1_787_000_000)
        let lengths = (1...4).map { index in
            SwimLengthPoint(
                index: index,
                start: start.addingTimeInterval(Double(index - 1) * 30),
                seconds: 30,
                meters: 25,
                followedRest: false
            )
        }
        let points = [SamplePoint(date: start, value: 100)]

        let metrics = WorkoutMetric.all(
            for: .swimming,
            samples: WorkoutSamples(distancePerMinute: points, swimLengths: lengths)
        )

        #expect(metrics.map(\.kind) == [.swimLengths, .swimPace])
        // 120 s over 100 m, from the lengths rather than the series.
        #expect(metrics.last?.headline == "2:00")
    }

    @Test("A provider without authorization refuses to hand over samples")
    func unauthorizedSamplesThrow() async {
        let provider = StubHealthDataProvider(status: .denied)

        await #expect(throws: HealthDataError.notAuthorized) {
            try await provider.samples(forWorkout: UUID())
        }
        await #expect(throws: HealthDataError.notAuthorized) {
            try await provider.hourlySteps(on: .now)
        }
    }

    @Test("Daily activity reports nothing when no movement was recorded")
    func emptyActivityIsReported() async throws {
        let provider = StubHealthDataProvider(activity: DailyActivity())

        let activity = try await provider.dailyActivity(on: .now)
        #expect(activity.hasAnything == false)
    }
}
