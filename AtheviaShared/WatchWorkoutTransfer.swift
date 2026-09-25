import Foundation

enum SharedAudioCoachingPreferences {
    static let enabledKey = "audioCoachingEnabled"
    static let countdownsKey = "audioCoachingCountdowns"
    static let volumeKey = "audioCoachingVolume"
}

struct WatchCoachingSettingsPayload: Codable, Equatable, Sendable {
    let enabled: Bool
    let countdowns: Bool
    let volume: Double

    static let defaults = WatchCoachingSettingsPayload(
        enabled: true,
        countdowns: true,
        volume: 0.8
    )
}

struct WatchWorkoutListPayload: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let generatedAt: Date
    let weekStart: Date?
    let workouts: [WatchWorkoutPayload]
    let coaching: WatchCoachingSettingsPayload?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        generatedAt: Date = .now,
        weekStart: Date?,
        workouts: [WatchWorkoutPayload],
        coaching: WatchCoachingSettingsPayload? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.weekStart = weekStart
        self.workouts = workouts
        self.coaching = coaching
    }
}

struct WatchWorkoutPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let discipline: WatchWorkoutDiscipline
    let title: String
    let goal: String
    let estimatedDurationSeconds: TimeInterval?
    let estimatedDistanceMeters: Double?
    let status: WatchWorkoutStatus
    let steps: [WatchWorkoutStepPayload]
}

enum WatchWorkoutDiscipline: String, Codable, Equatable, Sendable {
    case running
    case swimming
    case cycling
    case multisport

    var displayName: String {
        switch self {
        case .running: "Run"
        case .swimming: "Swim"
        case .cycling: "Cycle"
        case .multisport: "Multisport"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "figure.run"
        case .swimming: "figure.pool.swim"
        case .cycling: "figure.outdoor.cycle"
        case .multisport: "figure.mixed.cardio"
        }
    }
}

enum WatchWorkoutStatus: String, Codable, Equatable, Sendable {
    case planned
    case completed
    case skipped
}

struct WatchWorkoutStepPayload: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: WatchWorkoutStepKind
    let title: String
    let instructions: String?
    let durationSeconds: TimeInterval?
    let distanceMeters: Double?
    let targetIntensity: WatchWorkoutIntensity?
    let repeatCount: Int?
    let children: [WatchWorkoutStepPayload]
}

enum WatchWorkoutStepKind: String, Codable, Equatable, Sendable {
    case warmUp
    case work
    case recovery
    case cooldown
    case runningSegment
    case cyclingSegment
    case swimmingSegment
    case transition
    case repeatBlock

    var displayName: String {
        switch self {
        case .warmUp: "Warm-up"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cool-down"
        case .runningSegment: "Run"
        case .cyclingSegment: "Bike"
        case .swimmingSegment: "Swim"
        case .transition: "Transition"
        case .repeatBlock: "Repeat"
        }
    }
}

enum WatchWorkoutIntensity: String, Codable, Equatable, Sendable {
    case veryEasy
    case easy
    case steady
    case moderate
    case hard

    var displayName: String {
        switch self {
        case .veryEasy: "Very easy"
        case .easy: "Easy"
        case .steady: "Steady"
        case .moderate: "Moderate"
        case .hard: "Hard"
        }
    }
}

extension TimeInterval {
    var atheviaWatchDurationText: String {
        let totalMinutes = Int((self / 60).rounded())
        guard totalMinutes >= 60 else { return "\(max(totalMinutes, 1)) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }
}

extension Double {
    var atheviaWatchDistanceText: String {
        if self >= 1000 {
            let kilometres = self / 1000
            return kilometres.formatted(.number.precision(.fractionLength(kilometres < 10 ? 1 : 0))) + " km"
        }
        return Int(self.rounded()).formatted() + " m"
    }
}


extension WatchWorkoutStepKind {
    var segmentDiscipline: WatchWorkoutDiscipline? {
        switch self {
        case .runningSegment: .running
        case .cyclingSegment: .cycling
        case .swimmingSegment: .swimming
        default: nil
        }
    }

    var isTransition: Bool { self == .transition }
}
