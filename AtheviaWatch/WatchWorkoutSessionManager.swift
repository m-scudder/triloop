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
    @Published private(set) var engine: WatchWorkoutExecutionEngine?
    @Published private(set) var heartRate: Double?
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var currentSpeedMetersPerSecond: Double?
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var activeEnergyKilocalories: Double = 0
    @Published private(set) var savedWorkoutUUID: UUID?
    @Published var errorMessage: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var ticker: Task<Void, Never>?
    private var lastTickDate: Date?
    private var lastEngineDistanceMeters: Double = 0
    private var isFinalizing = false

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

    @discardableResult
    func start(_ workout: WatchWorkoutPayload) async -> Bool {
        if isActive {
            return activeWorkout?.id == workout.id
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "Health data is unavailable on this Apple Watch."
            return false
        }

        state = .preparing
        resetMetrics()
        activeWorkout = workout
        engine = WatchWorkoutExecutionEngine(workout: workout)

        do {
            try await requestAuthorization()

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = workout.discipline.healthKitActivityType
            configuration.locationType = workout.discipline.defaultLocationType

            let newSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            newSession.delegate = self
            newBuilder.delegate = self
            session = newSession
            builder = newBuilder

            let startDate = Date()
            newSession.startActivity(with: startDate)

            let began = await beginCollection(newBuilder, at: startDate)
            guard began else {
                newSession.end()
                errorMessage = "Athevia could not start recording this workout."
                state = .idle
                return false
            }

            newBuilder.addMetadata([
                AtheviaWorkoutMetadata.plannedWorkoutIDKey: workout.id.uuidString,
                AtheviaWorkoutMetadata.sourceKey: AtheviaWorkoutMetadata.sourceWatchValue
            ]) { _, _ in }

            engine?.start()
            state = .running
            lastTickDate = startDate
            lastEngineDistanceMeters = 0
            startTicker()
            WKInterfaceDevice.current().play(.start)
            return true
        } catch {
            errorMessage = error.localizedDescription
            state = .idle
            activeWorkout = nil
            engine = nil
            session = nil
            builder = nil
            return false
        }
    }

    func pause() {
        guard state == .running else { return }
        session?.pause()
        engine?.pause()
        state = .paused
        lastTickDate = nil
        WKInterfaceDevice.current().play(.click)
    }

    func resume() {
        guard state == .paused else { return }
        session?.resume()
        engine?.resume()
        state = .running
        lastTickDate = .now
        lastEngineDistanceMeters = distanceMeters
        WKInterfaceDevice.current().play(.click)
    }

    func completeCurrentStep() {
        guard state == .running || state == .paused else { return }
        let previousID = engine?.currentStep?.id
        engine?.completeCurrent()
        handleStepTransition(from: previousID)

        if engine?.phase == .finished {
            end()
        }
    }

    func end() {
        guard state == .running || state == .paused else { return }
        state = .ending
        ticker?.cancel()
        ticker = nil
        session?.end()
    }

    func reset() {
        guard !isActive else { return }
        ticker?.cancel()
        ticker = nil
        session = nil
        builder = nil
        activeWorkout = nil
        engine = nil
        savedWorkoutUUID = nil
        errorMessage = nil
        isFinalizing = false
        state = .idle
        resetMetrics()
    }

    func clearError() {
        errorMessage = nil
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

    private func beginCollection(_ builder: HKLiveWorkoutBuilder, at date: Date) async -> Bool {
        await withCheckedContinuation { continuation in
            builder.beginCollection(withStart: date) { success, _ in
                continuation.resume(returning: success)
            }
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

        if runningEngine.phase == .finished {
            end()
        }
    }

    private func handleStepTransition(from previousID: String?) {
        let currentID = engine?.currentStep?.id
        guard previousID != nil, previousID != currentID else { return }

        if currentID == nil {
            WKInterfaceDevice.current().play(.success)
        } else {
            WKInterfaceDevice.current().play(.notification)
        }
    }

    private func resetMetrics() {
        heartRate = nil
        averageHeartRate = nil
        currentSpeedMetersPerSecond = nil
        distanceMeters = 0
        activeEnergyKilocalories = 0
        lastEngineDistanceMeters = 0
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

        builder.endCollection(withEnd: endDate) { [weak self] success, error in
            guard success, error == nil else {
                Task { @MainActor in
                    guard let self else { return }
                    self.isFinalizing = false
                    self.state = .finished
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

                    if let finishError {
                        self.errorMessage = finishError.localizedDescription
                    }

                    WKInterfaceDevice.current().play(.success)
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
            self.errorMessage = error.localizedDescription
            self.state = .finished
        }
    }
}

extension WatchWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

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

    var defaultLocationType: HKWorkoutSessionLocationType {
        switch self {
        case .running, .cycling: .outdoor
        case .swimming: .unknown
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


private enum WatchWorkoutSessionError: LocalizedError {
    case healthWriteNotAuthorized

    var errorDescription: String? {
        switch self {
        case .healthWriteNotAuthorized:
            "Allow Athevia to write workouts to Apple Health before starting."
        }
    }
}
