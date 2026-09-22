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
            state = .running
            lastTickDate = startDate
            lastEngineDistanceMeters = 0
            observedPoolLapCount = 0
            startTicker()
            persistActiveState(force: true)

            if workout.discipline == .swimming {
                enableWaterLockIfSupported()
            }

            WKInterfaceDevice.current().play(.start)

            if voiceEnabled {
                voiceCoach.announceStart(engine?.currentStep)
            }

            return true
        } catch {
            errorMessage = error.localizedDescription
            state = .idle
            activeWorkout = nil
            activeConfiguration = nil
            engine = nil
            session = nil
            builder = nil
            voiceCoach.stop()
            return false
        }
    }

    func pause() {
        guard state == .running else { return }
        session?.pause()
        engine?.pause()
        state = .paused
        lastTickDate = nil
        voiceCoach.stop()
        persistActiveState(force: true)
        WKInterfaceDevice.current().play(.click)
    }

    func resume() {
        guard state == .paused else { return }
        session?.resume()
        engine?.resume()
        state = .running
        lastTickDate = .now
        lastEngineDistanceMeters = distanceMeters
        countdownAnnouncedStepID = nil

        if voiceEnabled {
            voiceCoach.announceResume(engine?.currentStep)
        }

        persistActiveState(force: true)
        WKInterfaceDevice.current().play(.click)
    }

    func toggleVoice() {
        voiceEnabled.toggle()
        voiceCoach.setEnabled(voiceEnabled)

        if voiceEnabled, state == .running {
            voiceCoach.announceStep(engine?.currentStep)
        }
        persistActiveState(force: true)
    }

    func completeCurrentStep() {
        guard state == .running || state == .paused else { return }
        let previousID = engine?.currentStep?.id
        engine?.completeCurrent()
        handleStepTransition(from: previousID)
        persistActiveState(force: true)

        if engine?.phase == .finished {
            end()
        }
    }

    func end() {
        guard state == .running || state == .paused else { return }
        state = .ending
        ticker?.cancel()
        ticker = nil
        voiceCoach.stop()
        session?.end()
    }

    func reset() {
        guard !isActive else { return }
        ticker?.cancel()
        ticker = nil
        voiceCoach.stop()
        session = nil
        builder = nil
        activeWorkout = nil
        activeConfiguration = nil
        engine = nil
        savedWorkoutUUID = nil
        errorMessage = nil
        isFinalizing = false
        countdownAnnouncedStepID = nil
        state = .idle
        clearPersistedActiveState()
        resetMetrics()
    }

    func clearError() {
        errorMessage = nil
    }

    func recoverIfNeeded() async {
        guard state == .idle,
              let persisted = loadPersistedActiveState() else {
            return
        }

        do {
            guard let recoveredSession = try await recoverActiveSession() else {
                clearPersistedActiveState()
                return
            }

            let recoveredBuilder = recoveredSession.associatedWorkoutBuilder()
            recoveredBuilder.shouldCollectWorkoutEvents = true
            let recoveredConfiguration = recoveredSession.workoutConfiguration
            recoveredBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: recoveredConfiguration
            )
            recoveredSession.delegate = self
            recoveredBuilder.delegate = self

            session = recoveredSession
            builder = recoveredBuilder
            activeWorkout = persisted.workout
            activeConfiguration = persisted.configuration
            coachingSettings = persisted.coaching
            voiceEnabled = persisted.voiceEnabled
            voiceCoach.configure(persisted.coaching)
            voiceCoach.setEnabled(persisted.voiceEnabled)
            savedWorkoutUUID = nil
            isFinalizing = false
            countdownAnnouncedStepID = nil

            var recoveredEngine = WatchWorkoutExecutionEngine(
                workout: persisted.workout,
                snapshot: persisted.execution
            )

            switch recoveredSession.state {
            case .running:
                if recoveredEngine.phase == .ready {
                    recoveredEngine.start()
                } else if recoveredEngine.phase == .paused {
                    recoveredEngine.resume()
                }

            case .paused:
                if recoveredEngine.phase == .running {
                    recoveredEngine.pause()
                }

            default:
                clearPersistedActiveState()
                session = nil
                builder = nil
                return
            }

            resetMetrics()
            refreshRecoveredStatistics()
            updatePoolDistanceFromLapEvents(recoveredBuilder)

            if recoveredEngine.phase == .running {
                let elapsedFromHealth = recoveredBuilder.elapsedTime(at: .now)
                let elapsedDelta = max(
                    elapsedFromHealth - persisted.execution.elapsedSeconds,
                    0
                )
                let distanceDelta = max(
                    distanceMeters - persisted.totalDistanceMeters,
                    0
                )
                recoveredEngine.advance(
                    by: elapsedDelta,
                    distanceDeltaMeters: distanceDelta
                )
            }

            engine = recoveredEngine
            state = recoveredSession.state == .paused ? .paused : .running
            lastTickDate = state == .running ? .now : nil
            lastEngineDistanceMeters = distanceMeters

            if state == .running {
                startTicker()
                if voiceEnabled {
                    voiceCoach.announceResume(engine?.currentStep)
                }
            }

            persistActiveState(force: true)
        } catch {
            clearPersistedActiveState()
            errorMessage = "Athevia could not recover the interrupted workout."
        }
    }

    private func recoverActiveSession() async throws -> HKWorkoutSession? {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.recoverActiveWorkoutSession { session, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: session)
                }
            }
        }
    }

    private func refreshRecoveredStatistics() {
        guard let builder, let workout = activeWorkout else { return }

        if let quantity = builder.statistics(
            for: workout.discipline.healthKitDistanceType
        )?.sumQuantity() {
            distanceMeters = quantity.doubleValue(for: .meter())
        }

        if let quantity = builder.statistics(
            for: HKQuantityType(.activeEnergyBurned)
        )?.sumQuantity() {
            activeEnergyKilocalories = quantity.doubleValue(for: .kilocalorie())
        }

        if let heartStatistics = builder.statistics(
            for: HKQuantityType(.heartRate)
        ) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            heartRate = heartStatistics.mostRecentQuantity()?.doubleValue(for: unit)
            averageHeartRate = heartStatistics.averageQuantity()?.doubleValue(for: unit)
        }

        if let speedType = workout.discipline.healthKitSpeedType,
           let quantity = builder.statistics(for: speedType)?.mostRecentQuantity() {
            currentSpeedMetersPerSecond = quantity.doubleValue(
                for: HKUnit.meter().unitDivided(by: .second())
            )
        }
    }

    private func persistActiveState(force: Bool = false, now: Date = .now) {
        guard let workout = activeWorkout,
              let configuration = activeConfiguration,
              let engine,
              engine.phase == .running || engine.phase == .paused else {
            return
        }

        if !force,
           let lastPersistedAt,
           now.timeIntervalSince(lastPersistedAt) < 5 {
            return
        }

        let persisted = PersistedWatchWorkoutState(
            workout: workout,
            configuration: configuration,
            coaching: coachingSettings,
            voiceEnabled: voiceEnabled,
            execution: engine.snapshot,
            totalDistanceMeters: distanceMeters
        )

        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: Self.activeStateKey)
        lastPersistedAt = now
    }

    private func loadPersistedActiveState() -> PersistedWatchWorkoutState? {
        guard let data = UserDefaults.standard.data(forKey: Self.activeStateKey) else {
            return nil
        }
        return try? JSONDecoder().decode(
            PersistedWatchWorkoutState.self,
            from: data
        )
    }

    private func clearPersistedActiveState() {
        UserDefaults.standard.removeObject(forKey: Self.activeStateKey)
        lastPersistedAt = nil
    }

    private func requestAuthorization() async throws {
        let workoutType = HKObjectType.workoutType()
        let shareTypes: Set<HKSampleType> = [workoutType]
        let readTypes: Set<HKObjectType> = [
            workoutType,
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.cyclingSpeed)
        ]

        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)

        guard healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized else {
            throw WatchWorkoutSessionError.healthWriteNotAuthorized
        }
    }

    private func healthKitConfiguration(
        for workout: WatchWorkoutPayload,
        startConfiguration: WatchWorkoutStartConfiguration
    ) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workout.discipline.healthKitActivityType

        switch workout.discipline {
        case .running, .cycling:
            configuration.locationType = startConfiguration.environment == .indoor
                ? .indoor
                : .outdoor

        case .swimming:
            // Swimming has its own location model. Do not also set the generic
            // indoor/outdoor location type; pool/open-water and lap length are
            // the configuration HealthKit uses for swim sensor collection.
            switch startConfiguration.environment {
            case .pool:
                configuration.swimmingLocationType = .pool
                let meters = normalizedPoolLength(
                    startConfiguration.poolLengthMeters
                )
                configuration.lapLength = HKQuantity(
                    unit: HKUnit.meter(),
                    doubleValue: meters
                )

            case .openWater:
                configuration.swimmingLocationType = .openWater
                configuration.lapLength = nil

            case .indoor:
                configuration.swimmingLocationType = .pool
                configuration.lapLength = HKQuantity(
                    unit: HKUnit.meter(),
                    doubleValue: 25
                )

            case .outdoor:
                configuration.swimmingLocationType = .openWater
                configuration.lapLength = nil
            }
        }

        return configuration
    }

    private func beginCollection(
        _ builder: HKLiveWorkoutBuilder,
        at date: Date
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            builder.beginCollection(withStart: date) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: WatchWorkoutSessionError.collectionCouldNotStart
                    )
                }
            }
        }
    }

    private func normalizedPoolLength(_ meters: Double?) -> Double {
        guard let meters, meters.isFinite else { return 25 }
        return min(max(meters, 10), 100)
    }

    private func enableWaterLockIfSupported() {
        #if !targetEnvironment(simulator)
        let device = WKInterfaceDevice.current()
        if device.waterResistanceRating == .wr50,
           !device.isWaterLockEnabled {
            device.enableWaterLock()
        }
        #endif
    }

    private func updatePoolDistanceFromLapEvents(
        _ workoutBuilder: HKLiveWorkoutBuilder
    ) {
        guard activeWorkout?.discipline == .swimming,
              activeConfiguration?.environment == .pool else {
            return
        }

        let poolLength = normalizedPoolLength(
            activeConfiguration?.poolLengthMeters
        )

        let lapCount = workoutBuilder.workoutEvents.filter {
            $0.type == .lap
        }.count

        guard lapCount > observedPoolLapCount else { return }
        observedPoolLapCount = lapCount

        // HealthKit's live distance sample can arrive after the lap event.
        // Never add the values together; use whichever source is further ahead.
        let eventDistance = Double(lapCount) * poolLength
        if eventDistance > distanceMeters {
            distanceMeters = eventDistance
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick(at now: Date = .now) {
        guard state == .running, var runningEngine = engine else { return }

        let previousID = runningEngine.currentStep?.id
        let previousTick = lastTickDate ?? now
        let seconds = max(now.timeIntervalSince(previousTick), 0)
        let distanceDelta = max(distanceMeters - lastEngineDistanceMeters, 0)

        runningEngine.advance(
            by: seconds,
            distanceDeltaMeters: distanceDelta
        )
        engine = runningEngine
        lastTickDate = now
        lastEngineDistanceMeters = distanceMeters

        handleStepTransition(from: previousID)
        announceCountdownIfNeeded()
        persistActiveState()

        if runningEngine.phase == .finished {
            end()
        }
    }

    private func announceCountdownIfNeeded() {
        guard voiceEnabled,
              coachingSettings.countdowns,
              let step = engine?.currentStep,
              let duration = step.durationSeconds,
              duration >= 30,
              let remaining = engine?.remainingSeconds,
              remaining > 0,
              remaining <= 10,
              countdownAnnouncedStepID != step.id else {
            return
        }

        countdownAnnouncedStepID = step.id
        voiceCoach.announceCountdown(nextStep: engine?.nextStep)
    }

    private func handleStepTransition(from previousID: String?) {
        let currentID = engine?.currentStep?.id
        guard previousID != nil, previousID != currentID else { return }

        countdownAnnouncedStepID = nil

        if currentID == nil {
            WKInterfaceDevice.current().play(.success)
            if voiceEnabled {
                voiceCoach.announceCompletion()
            }
        } else {
            WKInterfaceDevice.current().play(.notification)
            if voiceEnabled {
                voiceCoach.announceStep(engine?.currentStep)
            }
        }
    }

    private func resetMetrics() {
        heartRate = nil
        averageHeartRate = nil
        currentSpeedMetersPerSecond = nil
        distanceMeters = 0
        activeEnergyKilocalories = 0
        lastEngineDistanceMeters = 0
        observedPoolLapCount = 0
    }

    private func updateStatistics(for types: Set<HKSampleType>) {
        guard let builder, let workout = activeWorkout else { return }

        let heartRateType = HKQuantityType(.heartRate)
        if types.contains(heartRateType),
           let statistics = builder.statistics(for: heartRateType) {
            if let quantity = statistics.mostRecentQuantity() {
                heartRate = quantity.doubleValue(
                    for: HKUnit.count().unitDivided(by: .minute())
                )
            }
            if let average = statistics.averageQuantity() {
                averageHeartRate = average.doubleValue(
                    for: HKUnit.count().unitDivided(by: .minute())
                )
            }
        }

        let energyType = HKQuantityType(.activeEnergyBurned)
        if types.contains(energyType),
           let quantity = builder.statistics(for: energyType)?.sumQuantity() {
            activeEnergyKilocalories = quantity.doubleValue(for: .kilocalorie())
        }

        let distanceType = workout.discipline.healthKitDistanceType
        if types.contains(distanceType),
           let quantity = builder.statistics(for: distanceType)?.sumQuantity() {
            distanceMeters = quantity.doubleValue(for: .meter())
        }

        if let speedType = workout.discipline.healthKitSpeedType,
           types.contains(speedType),
           let quantity = builder.statistics(for: speedType)?.mostRecentQuantity() {
            currentSpeedMetersPerSecond = quantity.doubleValue(
                for: HKUnit.meter().unitDivided(by: .second())
            )
        }
    }

    private func finalizeWorkout(at endDate: Date) {
        guard !isFinalizing, let builder else {
            state = .finished
            return
        }

        isFinalizing = true
        ticker?.cancel()
        ticker = nil

        let totalSteps = engine?.plan.steps.count ?? 0
        let completedSteps = engine?.completedStepCount ?? 0
        let completion = engine?.prescriptionCompletionRatio ?? 0

        let adherenceMetadata: [String: Any] = [
            AtheviaWorkoutMetadata.prescriptionCompletionKey: completion,
            AtheviaWorkoutMetadata.completedStepsKey: completedSteps,
            AtheviaWorkoutMetadata.totalStepsKey: totalSteps
        ]

        builder.addMetadata(adherenceMetadata) { [weak self] _, _ in
            builder.endCollection(withEnd: endDate) { success, error in
                guard success, error == nil else {
                    Task { @MainActor in
                        guard let self else { return }
                        self.isFinalizing = false
                        self.state = .finished
                        self.clearPersistedActiveState()
                        self.errorMessage = "The workout ended, but HealthKit could not finalize its samples."
                    }
                    return
                }

                builder.finishWorkout { workout, finishError in
                    Task { @MainActor in
                        guard let self else { return }
                        self.isFinalizing = false
                        self.savedWorkoutUUID = workout?.uuid
                        self.engine?.finish()
                        self.state = .finished
                        self.session = nil
                        self.builder = nil
                        self.clearPersistedActiveState()

                        if let finishError {
                            self.errorMessage = finishError.localizedDescription
                        }

                        WKInterfaceDevice.current().play(.success)
                    }
                }
            }
        }
    }
}

extension WatchWorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }

        Task { @MainActor in
            self.finalizeWorkout(at: date)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.ticker?.cancel()
            self.ticker = nil
            self.voiceCoach.stop()
            self.clearPersistedActiveState()
            self.errorMessage = error.localizedDescription
            self.state = .finished
        }
    }
}

extension WatchWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        Task { @MainActor in
            self.updatePoolDistanceFromLapEvents(workoutBuilder)
        }
    }

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            self.updateStatistics(for: collectedTypes)
        }
    }
}

private extension WatchWorkoutDiscipline {
    var healthKitActivityType: HKWorkoutActivityType {
        switch self {
        case .running: .running
        case .cycling: .cycling
        case .swimming: .swimming
        }
    }

    var healthKitSpeedType: HKQuantityType? {
        switch self {
        case .running:
            HKQuantityType(.runningSpeed)
        case .cycling:
            HKQuantityType(.cyclingSpeed)
        case .swimming:
            nil
        }
    }

    var healthKitDistanceType: HKQuantityType {
        switch self {
        case .running: HKQuantityType(.distanceWalkingRunning)
        case .cycling: HKQuantityType(.distanceCycling)
        case .swimming: HKQuantityType(.distanceSwimming)
        }
    }
}

private struct PersistedWatchWorkoutState: Codable {
    let workout: WatchWorkoutPayload
    let configuration: WatchWorkoutStartConfiguration
    let coaching: WatchCoachingSettingsPayload
    let voiceEnabled: Bool
    let execution: WatchWorkoutExecutionSnapshot
    let totalDistanceMeters: Double
}

private enum WatchWorkoutSessionError: LocalizedError {
    case healthWriteNotAuthorized
    case collectionCouldNotStart

    var errorDescription: String? {
        switch self {
        case .healthWriteNotAuthorized:
            "Allow Athevia to write workouts to Apple Health before starting."
        case .collectionCouldNotStart:
            "Apple Watch could not start collecting workout data. Try starting the pool workout again."
        }
    }
}
