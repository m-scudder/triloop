import Foundation

struct WatchWorkoutStartConfiguration: Codable, Equatable, Sendable {
    enum Environment: String, Codable, CaseIterable, Identifiable, Sendable {
        case indoor
        case outdoor
        case pool
        case openWater

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .indoor: "Indoor"
            case .outdoor: "Outdoor"
            case .pool: "Pool"
            case .openWater: "Open Water"
            }
        }
    }

    var environment: Environment
    var poolLengthMeters: Double?

    static func defaultValue(for discipline: WatchWorkoutDiscipline) -> Self {
        switch discipline {
        case .running, .cycling:
            Self(environment: .outdoor, poolLengthMeters: nil)
        case .swimming:
            Self(environment: .pool, poolLengthMeters: 25)
        }
    }

    var displayName: String {
        if environment == .pool, let poolLengthMeters {
            return "\(Int(poolLengthMeters.rounded())) m Pool"
        }
        return environment.displayName
    }
}
