import Combine
import CoreLocation
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
    private let locationManager = CLLocationManager()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var routeInsertionTask: Task<Void, Never>?
    private var locationAuthorizationContinuation: CheckedContinuation<Bool, Never>?
    private var isRecordingRoute = false
    private var routeRecordingFailed = false
    private var lastAcceptedRouteLocation: CLLocation?
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

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 3
    }

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
        routeRecordingFailed = false
        lastAcceptedRouteLocation = nil
        let routeEligible = shouldRecordRoute(
            workout: workout,
            configuration: configuration
        )
        let recordsRoute = routeEligible
            ? await requestLocationAuthorization()
            : false

        do {
            let routeAuthorized = try await requestAuthorization(
                includeWorkoutRoute: recordsRoute
            )
            let shouldBuildRoute = recordsRoute && routeAuthorized

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

            if shouldBuildRoute {
                routeBuilder = newBuilder.seriesBuilder(
                    for: HKSeriesType.workoutRoute()
                ) as? HKWorkoutRouteBuilder
            } else {
                routeBuilder = nil
            }

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
            if routeBuilder != nil {
                startRouteLocationUpdates()
            }
            startTicker()
            persistActiveState(force: true)

            if workout.discipline == .swimming
                || engine?.currentStep?.kind.segmentDiscipline == .swimming {
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
            stopRouteLocationUpdates()
            routeBuilder = nil
            routeInsertionTask = nil
            isRecordingRoute = false
            voiceCoach.stop()
            return false
        }
    }

    func pause() {
        guard state == .running else { return }
        session?.pause()
        engine?.pause()
        stopRouteLocationUpdates()
        lastAcceptedRouteLocation = nil
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
        lastAcceptedRouteLocation = nil
        if routeBuilder != nil {
            startRouteLocationUpdates()
        }

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
        stopRouteLocationUpdates()
        session?.end()
    }

    func reset() {
        guard !isActive else { return }
        ticker?.cancel()
        ticker = nil
        voiceCoach.stop()
        stopRouteLocationUpdates()
        routeBuilder = nil
        routeInsertionTask = nil
        isRecordingRoute = false
        routeRecordingFailed = false
        lastAcceptedRouteLocation = nil
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

            if shouldRecordRoute(
                workout: persisted.workout,
                configuration: persisted.configuration
            ) {
                routeBuilder = recoveredBuilder.seriesBuilder(
                    for: HKSeriesType.workoutRoute()
                ) as? HKWorkoutRouteBuilder
                isRecordingRoute = routeBuilder != nil
                if state == .running {
                    startRouteLocationUpdates()
                }
            } else {
                routeBuilder = nil
                isRecordingRoute = false
            }

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
        guard let builder, activeWorkout != nil else { return }

        if let distanceType = metricDiscipline?.healthKitDistanceType,
           let quantity = builder.statistics(for: distanceType)?.sumQuantity() {
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

        if let speedType = metricDiscipline?.healthKitSpeedType,
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

    private func shouldRecordRoute(
        workout: WatchWorkoutPayload,
        configuration: WatchWorkoutStartConfiguration
    ) -> Bool {
        guard configuration.environment == .outdoor else { return false }
        switch workout.discipline {
        case .running, .cycling, .multisport:
            return true
        case .swimming:
            return false
        }
    }

    private func requestLocationAuthorization() async -> Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true

        case .notDetermined:
            return await withCheckedContinuation { continuation in
                locationAuthorizationContinuation = continuation
                locationManager.requestWhenInUseAuthorization()
            }

        case .denied, .restricted:
            return false

        @unknown default:
            return false
        }
    }

    private func handleLocationAuthorizationChange(
        _ status: CLAuthorizationStatus
    ) {
        let allowed = status == .authorizedAlways
            || status == .authorizedWhenInUse

        if status != .notDetermined,
           let continuation = locationAuthorizationContinuation {
            locationAuthorizationContinuation = nil
            continuation.resume(returning: allowed)
        }

        if allowed,
           isRecordingRoute,
           state == .running {
            startRouteLocationUpdates()
        } else if !allowed {
            stopRouteLocationUpdates()
        }
    }

    private func startRouteLocationUpdates() {
        guard routeBuilder != nil else { return }
        guard locationManager.authorizationStatus == .authorizedAlways
                || locationManager.authorizationStatus == .authorizedWhenInUse else {
            return
        }

        isRecordingRoute = true
        locationManager.startUpdatingLocation()
    }

    private func stopRouteLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }

    private func enqueueRouteLocations(_ locations: [CLLocation]) {
        guard isRecordingRoute,
              state == .running,
              let routeBuilder else {
            return
        }

        let now = Date()
        var filtered: [CLLocation] = []

        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= 35,
                  abs(location.timestamp.timeIntervalSince(now)) <= 15 else {
                continue
            }

            if let previous = lastAcceptedRouteLocation {
                let elapsed = location.timestamp.timeIntervalSince(previous.timestamp)
                guard elapsed > 0 else { continue }

                let speed = location.distance(from: previous) / elapsed
                guard speed <= maximumPlausibleRouteSpeed else { continue }
            }

            lastAcceptedRouteLocation = location
            filtered.append(location)
        }

        guard !filtered.isEmpty else { return }

        let previous = routeInsertionTask
        routeInsertionTask = Task { @MainActor [weak self] in
            await previous?.value
            do {
                try await routeBuilder.insertRouteData(filtered)
            } catch {
                self?.routeRecordingFailed = true
            }
        }
    }

    private func finishRouteIfNeeded(
        for workout: HKWorkout?
    ) async -> Error? {
        stopRouteLocationUpdates()
        lastAcceptedRouteLocation = nil

        let pendingInsert = routeInsertionTask
        await pendingInsert?.value
        routeInsertionTask = nil

        guard let routeBuilder else {
            isRecordingRoute = false
            return nil
        }

        self.routeBuilder = nil
        isRecordingRoute = false

        guard let workout else {
            return nil
        }

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                routeBuilder.finishRoute(
                    with: workout,
                    metadata: nil
                ) { route, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if route != nil {
                        continuation.resume()
                    } else {
                        continuation.resume(
                            throwing: WatchWorkoutSessionError.routeCouldNotFinish
                        )
                    }
                }
            }

            return routeRecordingFailed
                ? WatchWorkoutSessionError.routeDataCouldNotBeRecorded
                : nil
        } catch {
            return error
        }
    }

    private func requestAuthorization(
        includeWorkoutRoute: Bool
    ) async throws -> Bool {
        let workoutType = HKObjectType.workoutType()
        let routeType = HKSeriesType.workoutRoute()
        var shareTypes: Set<HKSampleType> = [workoutType]
        var readTypes: Set<HKObjectType> = [
            workoutType,
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.swimmingStrokeCount),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.runningPower),
            HKQuantityType(.runningStrideLength),
            HKQuantityType(.runningGroundContactTime),
            HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.cyclingSpeed),
            HKQuantityType(.cyclingCadence),
            HKQuantityType(.cyclingPower)
        ]

        if includeWorkoutRoute {
            shareTypes.insert(routeType)
            readTypes.insert(routeType)
        }

        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)

        guard healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized else {
            throw WatchWorkoutSessionError.healthWriteNotAuthorized
        }

        return includeWorkoutRoute
            && healthStore.authorizationStatus(for: routeType) == .sharingAuthorized
    }

    private var maximumPlausibleRouteSpeed: CLLocationSpeed {
        switch metricDiscipline {
        case .running:
            15
        case .cycling:
            45
        case .swimming:
            6
        case .multisport, nil:
            45
        }
    }

    private func healthKitConfiguration(
        for workout: WatchWorkoutPayload,
        startConfiguration: WatchWorkoutStartConfiguration
    ) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workout.discipline.healthKitActivityType

        switch workout.discipline {
        case .running, .cycling, .multisport:
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

    private func beginMultisportActivityIfNeeded(at date: Date) {
        guard activeWorkout?.discipline == .multisport,
              let step = engine?.currentStep,
              let configuration = multisportActivityConfiguration(for: step),
              let session else {
            return
        }

        let key = multisportActivityKey(for: step)
        guard activeMultisportActivityKey != key else { return }

        session.beginNewActivity(
            configuration: configuration,
            date: date,
            metadata: nil
        )
        activeMultisportActivityKey = key
        multisportSegmentStartedAtElapsedSeconds = engine?.elapsedSeconds ?? 0
        distanceMeters = 0
        currentSpeedMetersPerSecond = nil
        lastEngineDistanceMeters = 0
        observedPoolLapCount = 0

        if step.kind.segmentDiscipline == .swimming {
            enableWaterLockIfSupported()
        }
    }

    private func multisportActivityKey(for step: WatchExecutableWorkoutStep) -> String {
        if step.kind.isTransition { return "transition" }
        return step.kind.segmentDiscipline?.rawValue ?? "other"
    }

    private func multisportActivityConfiguration(
        for step: WatchExecutableWorkoutStep
    ) -> HKWorkoutConfiguration? {
        let configuration = HKWorkoutConfiguration()

        if step.kind.isTransition {
            configuration.activityType = .transition
            configuration.locationType = .outdoor
            return configuration
        }

        guard let discipline = step.kind.segmentDiscipline else { return nil }
        configuration.activityType = discipline.healthKitActivityType

        switch discipline {
        case .running, .cycling:
            configuration.locationType = activeConfiguration?.environment == .indoor
                ? .indoor
                : .outdoor

        case .swimming:
            let pool = activeConfiguration?.environment == .pool
            configuration.swimmingLocationType = pool ? .pool : .openWater
            if pool {
                configuration.lapLength = HKQuantity(
                    unit: .meter(),
                    doubleValue: normalizedPoolLength(activeConfiguration?.poolLengthMeters)
                )
            }

        case .multisport:
            return nil
        }

        return configuration
    }

    private func beginCollection(
        _ builder: HKLiveWorkoutBuilder,
        at date: Date
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
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
        let isPoolSwim = activeWorkout?.discipline == .swimming
            && activeConfiguration?.environment == .pool
        let isMultisportPoolSwim = activeWorkout?.discipline == .multisport
            && engine?.currentStep?.kind.segmentDiscipline == .swimming
            && activeConfiguration?.environment == .pool
        guard isPoolSwim || isMultisportPoolSwim else {
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

        if activeWorkout?.discipline == .multisport {
            beginMultisportActivityIfNeeded(at: .now)
        }

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
        activeMultisportActivityKey = nil
        multisportSegmentStartedAtElapsedSeconds = 0
    }

    private var metricDiscipline: WatchWorkoutDiscipline? {
        guard let workout = activeWorkout else { return nil }
        if workout.discipline == .multisport {
            return engine?.currentStep?.kind.segmentDiscipline
        }
        return workout.discipline
    }

    private func updateStatistics(for types: Set<HKSampleType>) {
        guard let builder, activeWorkout != nil else { return }

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

        if let discipline = metricDiscipline,
           let distanceType = discipline.healthKitDistanceType {
            if types.contains(distanceType),
               let quantity = builder.statistics(for: distanceType)?.sumQuantity() {
                distanceMeters = quantity.doubleValue(for: .meter())
            }
        } else {
            distanceMeters = 0
        }

        if let speedType = metricDiscipline?.healthKitSpeedType,
           types.contains(speedType),
           let quantity = builder.statistics(for: speedType)?.mostRecentQuantity() {
            currentSpeedMetersPerSecond = quantity.doubleValue(
                for: HKUnit.meter().unitDivided(by: .second())
            )
        } else if metricDiscipline == nil {
            currentSpeedMetersPerSecond = nil
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
                        self.stopRouteLocationUpdates()
                        self.routeBuilder = nil
                        self.routeInsertionTask = nil
                        self.isRecordingRoute = false
                        self.clearPersistedActiveState()
                        self.errorMessage = "The workout ended, but HealthKit could not finalize its samples."
                    }
                    return
                }

                builder.finishWorkout { workout, finishError in
                    Task { @MainActor in
                        guard let self else { return }

                        let routeError = await self.finishRouteIfNeeded(
                            for: workout
                        )

                        self.isFinalizing = false
                        self.savedWorkoutUUID = workout?.uuid
                        self.engine?.finish()
                        self.state = .finished
                        self.session = nil
                        self.builder = nil
                        self.clearPersistedActiveState()

                        if let finishError {
                            self.errorMessage = finishError.localizedDescription
                        } else if let routeError {
                            self.errorMessage =
                                "The workout was saved, but its GPS route could not be saved. " +
                                routeError.localizedDescription
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
            self.stopRouteLocationUpdates()
            self.routeBuilder = nil
            self.routeInsertionTask = nil
            self.isRecordingRoute = false
            self.clearPersistedActiveState()
            self.errorMessage = error.localizedDescription
            self.state = .finished
        }
    }
}

extension WatchWorkoutSessionManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleLocationAuthorizationChange(status)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            self.enqueueRouteLocations(locations)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        guard let locationError = error as? CLError,
              locationError.code != .locationUnknown else {
            return
        }

        Task { @MainActor in
            guard self.isRecordingRoute else { return }
            self.routeRecordingFailed = true
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
        case .multisport: .swimBikeRun
        }
    }

    var healthKitSpeedType: HKQuantityType? {
        switch self {
        case .running:
            HKQuantityType(.runningSpeed)
        case .cycling:
            HKQuantityType(.cyclingSpeed)
        case .swimming, .multisport:
            nil
        }
    }

    var healthKitDistanceType: HKQuantityType? {
        switch self {
        case .running: HKQuantityType(.distanceWalkingRunning)
        case .cycling: HKQuantityType(.distanceCycling)
        case .swimming: HKQuantityType(.distanceSwimming)
        case .multisport: nil
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
    case routeDataCouldNotBeRecorded
    case routeCouldNotFinish
    case collectionCouldNotStart

    var errorDescription: String? {
        switch self {
        case .healthWriteNotAuthorized:
            "Allow Athevia to write workouts to Apple Health before starting."
        case .routeDataCouldNotBeRecorded:
            "Some GPS points could not be recorded."
        case .routeCouldNotFinish:
            "HealthKit could not finalize the workout route."
        case .collectionCouldNotStart:
            "Apple Watch could not start collecting workout data. Try starting the workout again."
        }
    }
}
