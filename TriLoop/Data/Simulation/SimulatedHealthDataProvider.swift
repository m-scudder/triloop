#if DEBUG
import Foundation

/// A `HealthDataProviding` backed by a fixture instead of HealthKit.
///
/// This sits *at* the provider boundary rather than inside the views, so every
/// importer, matcher, analysis and screen downstream runs the exact production
/// code path. Nothing in the app can tell the difference — which is the point:
/// a bug seen against simulated data is a real bug.
struct SimulatedHealthDataProvider: HealthDataProviding {
    let dataset: SimulationDataset
    /// "As of" date the fixture was generated for. Explicit so a test can pin it.
    let referenceDate: Date
    private let data: SimulatedHealthData

    init(
        dataset: SimulationDataset = SimulationSettings.dataset,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) {
        self.dataset = dataset
        self.referenceDate = referenceDate
        self.data = SimulationFixture.generate(dataset, asOf: referenceDate, calendar: calendar)
    }

    var authorizationStatus: HealthAuthorizationStatus {
        get async { data.authorization }
    }

    func requestAuthorization() async throws {
        guard data.authorization != .unavailable else {
            throw HealthDataError.unavailableOnThisDevice
        }
    }

    func workouts(from startDate: Date, to endDate: Date) async throws -> [ImportedWorkout] {
        try requireAuthorization()
        return data.workouts
            .filter { $0.startDate >= startDate && $0.startDate <= endDate }
            .sorted { $0.startDate > $1.startDate }
    }

    func dailyActivity(on date: Date) async throws -> DailyActivity {
        try requireAuthorization()
        let day = Calendar.current.startOfDay(for: date)
        let steps = data.dailySteps.first { Calendar.current.isDate($0.date, inSameDayAs: day) }?.value
        // Missing days report nil rather than zero: "no data" and "did not move"
        // are different answers and Phase 9 must never conflate them.
        guard let steps else { return DailyActivity() }
        return DailyActivity(steps: Int(steps), distanceMeters: steps * 0.72)
    }

    func samples(forWorkout id: UUID) async throws -> WorkoutSamples {
        try requireAuthorization()
        return data.samples[id] ?? WorkoutSamples()
    }

    func hourlySteps(on date: Date) async throws -> [SamplePoint] {
        try requireAuthorization()
        let calendar = Calendar.current
        return data.hourlySteps.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func dailySteps(from startDate: Date, to endDate: Date) async throws -> [SamplePoint] {
        try requireAuthorization()
        return data.dailySteps.filter { $0.date >= startDate && $0.date <= endDate }
    }

    private func requireAuthorization() throws {
        guard data.authorization == .authorized else { throw HealthDataError.notAuthorized }
    }
}

extension SimulatedHealthDataProvider: HealthHistoryReading {
    func workoutHistory(from startDate: Date, to endDate: Date) async throws -> [HealthWorkoutRecord] {
        try requireAuthorization()
        return data.workouts
            .filter { $0.startDate >= startDate && $0.startDate <= endDate }
            .sorted { $0.startDate > $1.startDate }
            .map { workout in
                HealthWorkoutRecord(
                    id: workout.healthKitUUID,
                    activityName: workout.sport.displayName,
                    sport: workout.sport,
                    start: workout.startDate,
                    end: workout.endDate,
                    duration: workout.duration,
                    distanceMeters: workout.distanceMeters,
                    averageHeartRate: workout.averageHeartRate,
                    energyKilocalories: workout.duration / 60 * 9,
                    swimmingLengths: workout.swimmingLengths,
                    metrics: workout.metrics,
                    sourceName: "Simulated"
                )
            }
    }
}

/// Which fixture the app is running on, and whether simulation is on at all.
///
/// Stored in `UserDefaults` rather than SwiftData: it is a developer setting,
/// not athlete data, and must never survive into a real training history.
enum SimulationSettings {
    private static let datasetKey = "simulationDataset"

    static var dataset: SimulationDataset {
        get {
            UserDefaults.standard.string(forKey: datasetKey)
                .flatMap(SimulationDataset.init(rawValue:)) ?? .beginnerTwelveWeeks
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: datasetKey) }
    }
}
#endif
