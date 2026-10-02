import Combine
import Foundation
import HealthKit
import WatchKit

@MainActor
final class WatchWorkoutSessionManager: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case running
        case paused
        case ending
        case finished
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var activeWorkout: WatchWorkoutPayload?
    @Published private(set) var activeConfiguration: WatchWorkoutStartConfiguration?
    @Published private(set) var engine: WatchWorkoutExecutionEngine?
    @Published private(set) var heartRate: Double?
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var currentSpeedMetersPerSecond: Double?
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var activeEnergyKilocalories: Double = 0
    @Published private(set) var savedWorkoutUUID: UUID?
    @Published private(set) var voiceEnabled = true
    @Published var errorMessage: String?

    private let healthStore = HKHealthStore()
    private let voiceCoach = WatchWorkoutVoiceCoach()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var ticker: Task<Void, Never>?
    private var lastTickDate: Date?
    private var lastEngineDistanceMeters: Double = 0
    private var observedPoolLapCount = 0
    private var isFinalizing = false
    private var coachingSettings: WatchCoachingSettingsPayload = .defaults
    private var countdownAnnouncedStepID: String?
    private var activeMultisportActivityKey: String?
    private var multisportSegmentStartedAtElapsedSeconds: TimeInterval = 0
    private var lastPersistedAt: Date?

    private static let activeStateKey = "athevia.active-watch-workout.v1"

    var isActive: Bool {
        switch state {
        case .preparing, .running, .paused, .ending:
            true
        case .idle, .finished:
            false
        }
    }

    var elapsedSeconds: TimeInterval {
        engine?.elapsedSeconds ?? 0
    }

    var currentStep: WatchExecutableWorkoutStep? {
        engine?.currentStep
    }

    var currentMetricDiscipline: WatchWorkoutDiscipline? {
        metricDiscipline
    }

    var segmentElapsedSeconds: TimeInterval {
        guard activeWorkout?.discipline == .multisport else { return elapsedSeconds }
        return max(elapsedSeconds - multisportSegmentStartedAtElapsedSeconds, 0)
    }

    var nextStep: WatchExecutableWorkoutStep? {
        engine?.nextStep
    }

    var completedPlannedWorkoutID: UUID? {
        guard savedWorkoutUUID != nil else { return nil }
        return activeWorkout?.id
    }

    @discardableResult
    func start(
        _ workout: WatchWorkoutPayload,
        configuration: WatchWorkoutStartConfiguration,
        coaching: WatchCoachingSettingsPayload
    ) async -> Bool {
        if isActive {
            return activeWorkout?.id == workout.id
        }

        guard workout.isScheduledForToday() else {
            errorMessage = "Only workouts scheduled for today can be started from Athevia Watch."
            return false
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data is unavailable on this Apple Watch."
            return false
        }

        state = .preparing
        resetMetrics()
        savedWorkoutUUID = nil
        activeWorkout = workout
        activeConfiguration = configuration
        engine = WatchWorkoutExecutionEngine(workout: workout)
        coachingSettings = coaching
        voiceEnabled = coaching.enabled
        voiceCoach.configure(coaching)
        countdownAnnouncedStepID = nil

        do {
            try await requestAuthorization()

            let workoutConfiguration = healthKitConfiguration(
                for: workout,
                startConfiguration: configuration
            )

            let newSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: workoutConfiguration
            )
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.shouldCollectWorkoutEvents = true
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: workoutConfiguration
            )

            newSession.delegate = self
            newBuilder.delegate = self
            session = newSession
            builder = newBuilder

            let startDate = Date()
            newSession.startActivity(with: startDate)

            try await beginCollection(newBuilder, at: startDate)

            var workoutMetadata: [String: Any] = [
                AtheviaWorkoutMetadata.plannedWorkoutIDKey: workout.id.uuidString,
                AtheviaWorkoutMetadata.sourceKey: AtheviaWorkoutMetadata.sourceWatchValue
            ]

            if workout.discipline == .swimming {
                workoutMetadata[HKMetadataKeySwimmingLocationType] = NSNumber(
                    value: workoutConfiguration.swimmingLocationType.rawValue
                )

                if workoutConfiguration.swimmingLocationType == .pool,
                   let lapLength = workoutConfiguration.lapLength {
                    workoutMetadata[HKMetadataKeyLapLength] = lapLength
                }
            }

            newBuilder.addMetadata(workoutMetadata) { _, _ in }

            engine?.start()
            if workout.discipline == .multisport {
                beginMultisportActivityIfNeeded(at: startDate)
            }
            state = .running
            lastTickDate = startDate
            lastEngineDistanceMeters = 0
            observedPoolLapCount = 0
            startTicker()
            persistActiveState(force: true)

            if workout.discipline == .swimming
                || engine?.currentStep?.kind.segmentDiscipline == .swimming {
                enableWaterLockIfSupported()
            }
