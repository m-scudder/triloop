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
}

/// Fixed data for previews, tests and Developer Mode.
struct StubHealthDataProvider: HealthDataProviding {
    var status: HealthAuthorizationStatus = .authorized
    var stored: [ImportedWorkout] = []

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
}
