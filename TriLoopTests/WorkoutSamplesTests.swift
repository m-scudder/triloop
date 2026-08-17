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
        let length = SwimLengthPoint(index: 1, seconds: 30, meters: 25, followedRest: false)

        #expect(length.pacePer100m == 120)
    }

    @Test("A length with no distance has no pace rather than a divide by zero")
    func zeroDistanceHasNoPace() {
        let length = SwimLengthPoint(index: 1, seconds: 30, meters: 0, followedRest: false)

        #expect(length.pacePer100m == 0)
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
