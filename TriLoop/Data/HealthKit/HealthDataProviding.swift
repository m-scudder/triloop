import Foundation

enum HealthAuthorizationStatus: Equatable, Sendable {
    case unavailable
    case notDetermined
    case denied
    case authorized
}

enum HealthDataError: Error, Equatable {
    case unavailableOnThisDevice
    case notAuthorized
}

/// All-day movement, outside of any planned session.
///
/// Read live and never stored: it is context for the athlete rather than an
/// input to the training engine, and HealthKit already keeps the history.
struct DailyActivity: Equatable, Sendable {
    var steps: Int?
    var distanceMeters: Double?

    var hasAnything: Bool { steps != nil || distanceMeters != nil }
}

/// §24's boundary for health data.
///
/// Deliberately small: TriLoop reads completed workouts and nothing else. Any
/// implementation can be swapped in for tests, previews or Developer Mode
/// without HealthKit being involved.
protocol HealthDataProviding: Sendable {
    var authorizationStatus: HealthAuthorizationStatus { get async }

    func requestAuthorization() async throws

    /// Completed workouts in the three sports TriLoop trains, most recent first.
    func workouts(from startDate: Date, to endDate: Date) async throws -> [ImportedWorkout]

    func dailyActivity(on date: Date) async throws -> DailyActivity

    /// Time series behind one completed workout, looked up by its HealthKit id.
    func samples(forWorkout id: UUID) async throws -> WorkoutSamples

    /// Steps bucketed by hour for a single day.
    func hourlySteps(on date: Date) async throws -> [SamplePoint]

    /// Steps bucketed by day across a range, for week and month views.
    func dailySteps(from startDate: Date, to endDate: Date) async throws -> [SamplePoint]
}

/// Fixed data for previews, tests and Developer Mode.
struct StubHealthDataProvider: HealthDataProviding {
    var status: HealthAuthorizationStatus = .authorized
    var stored: [ImportedWorkout] = []
    var activity: DailyActivity = DailyActivity(steps: 6_240, distanceMeters: 4_100)
    var samples: WorkoutSamples = WorkoutSamples()
    var hourly: [SamplePoint] = []
    var daily: [SamplePoint] = []

    var authorizationStatus: HealthAuthorizationStatus {
        get async { status }
    }

    func requestAuthorization() async throws {
        guard status != .unavailable else { throw HealthDataError.unavailableOnThisDevice }
    }

    func workouts(from startDate: Date, to endDate: Date) async throws -> [ImportedWorkout] {
        guard status == .authorized else { throw HealthDataError.notAuthorized }
        return stored
            .filter { $0.startDate >= startDate && $0.startDate <= endDate }
            .sorted { $0.startDate > $1.startDate }
    }

    func dailyActivity(on date: Date) async throws -> DailyActivity {
        guard status == .authorized else { throw HealthDataError.notAuthorized }
        return activity
    }

    func samples(forWorkout id: UUID) async throws -> WorkoutSamples {
        guard status == .authorized else { throw HealthDataError.notAuthorized }
        return samples
    }

    func hourlySteps(on date: Date) async throws -> [SamplePoint] {
        guard status == .authorized else { throw HealthDataError.notAuthorized }
        return hourly
    }

    func dailySteps(from startDate: Date, to endDate: Date) async throws -> [SamplePoint] {
        guard status == .authorized else { throw HealthDataError.notAuthorized }
        return daily
    }
}
