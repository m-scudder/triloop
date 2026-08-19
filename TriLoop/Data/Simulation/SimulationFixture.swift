#if DEBUG
import Foundation

/// Builds a dataset's health history.
///
/// Reference-date driven and free of `Date()`: the caller states "as of when",
/// so a fixture is reproducible tomorrow and in a test.
enum SimulationFixture {

    static func generate(
        _ dataset: SimulationDataset,
        asOf referenceDate: Date,
        calendar: Calendar = .current
    ) -> SimulatedHealthData {
        guard dataset != .noData else {
            return SimulatedHealthData(authorization: .authorized)
        }

        var generator = DeterministicGenerator(seed: seed(for: dataset))
        var data = SimulatedHealthData()

        let today = calendar.startOfDay(for: referenceDate)
        let days = dataset.weeks * 7

        for dayOffset in stride(from: days - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let weekIndex = (days - 1 - dayOffset) / 7

            guard let sport = sport(for: dataset, dayOffset: dayOffset, generator: &generator) else { continue }

            let workout = makeWorkout(
                sport: sport,
                on: date,
                weekIndex: weekIndex,
                dataset: dataset,
                calendar: calendar,
                generator: &generator
            )
            data.workouts.append(workout)
            data.samples[workout.healthKitUUID] = makeSamples(
                for: workout,
                dataset: dataset,
                generator: &generator
            )
        }

        data.dailySteps = makeDailySteps(days: max(days, 28), endingAt: today, calendar: calendar, generator: &generator)
        data.hourlySteps = makeHourlySteps(on: today, calendar: calendar, generator: &generator)
        data.recovery = makeRecovery(dataset, endingAt: today, calendar: calendar, generator: &generator)
        data.authorization = dataset == .partialData ? .authorized : .authorized

        return data
    }

    /// Daily recovery readings for the metrics a fixture claims to provide.
    ///
    /// The poor-recovery dataset trends resting heart rate up while HRV and
    /// sleep fall, so §43's "below your recent range" language has something
    /// real to describe.
    private static func makeRecovery(
        _ dataset: SimulationDataset,
        endingAt today: Date,
        calendar: Calendar,
        generator: inout DeterministicGenerator
    ) -> [RecoveryMetric: [SamplePoint]] {
        var result: [RecoveryMetric: [SamplePoint]] = [:]
        let days = dataset.recoveryDays
        guard days > 0 else { return result }

        for metric in RecoveryMetric.allCases where dataset.provides(metric) {
            var points: [SamplePoint] = []

            for offset in stride(from: days - 1, through: 0, by: -1) {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }

                // Cardio fitness is estimated occasionally, not daily, so
                // sampling it every day would misrepresent how HealthKit works.
                if metric == .cardioFitness, offset % 7 != 0 { continue }

                let progress = Double(days - 1 - offset) / Double(max(days - 1, 1))
                points.append(
                    SamplePoint(
                        date: date,
                        value: value(for: metric, dataset: dataset, progress: progress, generator: &generator)
                    )
                )
            }

            result[metric] = points
        }

        return result
    }

    private static func value(
        for metric: RecoveryMetric,
        dataset: SimulationDataset,
        progress: Double,
        generator: inout DeterministicGenerator
    ) -> Double {
        let declining = dataset == .poorRecovery
        let trend = declining ? progress : 0

        return switch metric {
        case .restingHeartRate:
            (52 + trend * 9 + generator.value(in: -1.5...1.5)).rounded()
        case .heartRateVariability:
            (48 - trend * 14 + generator.value(in: -4...4)).rounded()
        case .sleepDuration:
            max(3.5, 7.4 - trend * 1.8 + generator.value(in: -0.6...0.6))
        case .cardioFitness:
            (dataset.hasPower ? 52.0 : 41.0) + generator.value(in: -0.4...0.4)
        case .heartRateRecovery:
            (32 - trend * 8 + generator.value(in: -2...2)).rounded()
        }
    }

    /// Fixed per dataset, so two datasets differ but one dataset never does.
    ///
    /// Derived from the case's position, not `hashValue`: Swift seeds string
    /// hashing per process, so a hash-based seed would silently change between
    /// launches and destroy the determinism this whole file exists for.
    private static func seed(for dataset: SimulationDataset) -> UInt64 {
        let ordinal = SimulationDataset.allCases.firstIndex(of: dataset) ?? 0
        return UInt64(ordinal + 1) &* 0x9E3779B9
    }

    /// Stable ordinal for a sport, for the same reason.
    private static func ordinal(of sport: Sport) -> Int {
        switch sport {
        case .running: 1
        case .swimming: 2
        case .cycling: 3
        }
    }

    /// Which sport falls on a day, if any. Rest days are the gaps.
    private static func sport(
        for dataset: SimulationDataset,
        dayOffset: Int,
        generator: inout DeterministicGenerator
    ) -> Sport? {
        let sports = dataset.sports
        guard !sports.isEmpty else { return nil }

        let weekday = dayOffset % 7

        if dataset == .sparseHistory {
            return weekday == 2 ? sports[0] : nil
        }

        // Roughly four sessions a week, spread rather than consecutive.
        switch weekday {
        case 0, 2, 4, 5: return sports[(dayOffset / 2) % sports.count]
        default: return nil
        }
    }

    private static func makeWorkout(
        sport: Sport,
        on date: Date,
        weekIndex: Int,
        dataset: SimulationDataset,
        calendar: Calendar,
        generator: inout DeterministicGenerator
    ) -> ImportedWorkout {
        let start = calendar.date(bySettingHour: 7, minute: 15, second: 0, of: date) ?? date
        let duration = self.duration(sport: sport, weekIndex: weekIndex, dataset: dataset)
        let heartRate = dataset.hasHeartRate
            ? averageHeartRate(sport: sport, dataset: dataset, generator: &generator)
            : nil

        return ImportedWorkout(
            healthKitUUID: uuid(for: date, sport: sport),
            sport: sport,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            duration: duration,
            distanceMeters: distance(sport: sport, seconds: duration),
            averageHeartRate: heartRate,
            maximumHeartRate: heartRate.map { $0 + 18 },
            elevationAscendedMeters: sport == .cycling ? 60 + Double(weekIndex) * 4 : nil,
            swimmingLengths: sport == .swimming ? Int((distance(sport: .swimming, seconds: duration) ?? 0) / 25) : nil,
            swimmingStrokeCount: sport == .swimming ? 19 * Double(weekIndex + 8) : nil,
            longestContinuousSwimMeters: sport == .swimming ? Double(25 * (1 + weekIndex / 3)) : nil,
            metrics: makeMetrics(sport: sport, dataset: dataset, weekIndex: weekIndex, seconds: duration),
            source: "com.apple.workout"
        )
    }

    /// Sport-specific sensor values, gated by what the fixture claims to own.
    ///
    /// A dataset without power must produce no watts anywhere, or the
    /// missing-data paths §59 exists to test are never exercised.
    private static func makeMetrics(
        sport: Sport,
        dataset: SimulationDataset,
        weekIndex: Int,
        seconds: TimeInterval
    ) -> RecordedMetrics {
        var metrics = RecordedMetrics()

        if dataset.hasEffortScore {
            metrics.estimatedWorkoutEffort = Double(min(4 + weekIndex / 4, 10))
        }

        switch sport {
        case .running:
            metrics.averageCadence = 158 + Double(weekIndex)
            metrics.averageRunningSpeed = 2.4
            if dataset.hasRunningDynamics {
                metrics.averageRunningPower = 210 + Double(weekIndex) * 2
                metrics.averageStrideLength = 0.95 + Double(weekIndex) * 0.01
                metrics.averageGroundContactTime = 265 - Double(weekIndex)
                metrics.averageVerticalOscillation = 8.4
            }

        case .cycling:
            metrics.averageCyclingSpeed = 6.4
            metrics.averageCyclingCadence = 82 + Double(weekIndex % 5)
            if dataset.hasPower {
                metrics.averageCyclingPower = 165 + Double(weekIndex) * 3
                metrics.functionalThresholdPower = 220
            }

        case .swimming:
            break
        }

        return metrics
    }

    /// Stable across runs: the same day and sport always yield the same id, so
    /// re-importing a fixture is correctly treated as a duplicate.
    private static func uuid(for date: Date, sport: Sport) -> UUID {
        let stamp = UInt32(truncatingIfNeeded: Int(date.timeIntervalSince1970))
        let text = String(format: "%08x-0000-4000-8000-%012d", stamp, ordinal(of: sport))
        return UUID(uuidString: text) ?? UUID()
    }

    private static func duration(sport: Sport, weekIndex: Int, dataset: SimulationDataset) -> TimeInterval {
        let progression = Double(weekIndex)

        switch (sport, dataset) {
        case (.running, .experiencedRunner), (.running, .experiencedTriathlete):
            return (45 + progression) * 60
        case (.running, _):
            return (25 + progression * 1.5) * 60
        case (.swimming, _):
            return (30 + progression) * 60
        case (.cycling, .powerCyclist), (.cycling, .experiencedTriathlete):
            return (75 + progression * 2) * 60
        case (.cycling, _):
            return (25 + progression * 2.5) * 60
        }
    }

    private static func distance(sport: Sport, seconds: TimeInterval) -> Double? {
        switch sport {
        case .running: seconds * 2.4
        case .cycling: seconds * 6.4
        case .swimming: (seconds / 60) * 25
        }
    }

    private static func averageHeartRate(
        sport: Sport,
        dataset: SimulationDataset,
        generator: inout DeterministicGenerator
    ) -> Double {
        // Conflicting signals: comfortable heart rate against a hard report.
        let base: Double = switch dataset {
        case .conflictingSignals: 118
        case .highLoad: 158
        case .poorRecovery: 152
        default: sport == .running ? 146 : (sport == .cycling ? 132 : 138)
        }
        return base + generator.value(in: -4...4).rounded()
    }

    private static func makeSamples(
        for workout: ImportedWorkout,
        dataset: SimulationDataset,
        generator: inout DeterministicGenerator
    ) -> WorkoutSamples {
        let minutes = max(Int(workout.duration / 60), 1)
        let start = workout.startDate

        let heartRate: [SamplePoint] = dataset.hasHeartRate
            ? (0..<minutes).map { minute in
                let progress = Double(minute) / Double(max(minutes - 1, 1))
                let warmUp = min(progress * 4, 1)
                let drift = progress * 8
                let base = (workout.averageHeartRate ?? 140) - 12
                return SamplePoint(
                    date: start.addingTimeInterval(Double(minute) * 60),
                    value: (base + (24 * warmUp) + drift).rounded()
                )
            }
            : []

        let cadence: [SamplePoint] = workout.sport == .running
            ? (0..<minutes).map { minute in
                SamplePoint(
                    date: start.addingTimeInterval(Double(minute) * 60),
                    value: (workout.metrics.averageCadence ?? 160) + generator.value(in: -3...3).rounded()
                )
            }
            : []

        let perMinute = (workout.distanceMeters ?? 0) / Double(minutes)
        let distance: [SamplePoint] = workout.sport == .swimming
            ? []
            : (0..<minutes).map { minute in
                SamplePoint(
                    date: start.addingTimeInterval(Double(minute) * 60),
                    value: (perMinute + generator.value(in: -8...8)).rounded()
                )
            }

        return WorkoutSamples(
            heartRate: heartRate,
            cadence: cadence,
            distancePerMinute: distance,
            energy: (0..<minutes).map { minute in
                SamplePoint(
                    date: start.addingTimeInterval(Double(minute) * 60),
                    value: (9 + generator.value(in: -2...2)).rounded()
                )
            },
            swimLengths: workout.sport == .swimming
                ? makeLengths(for: workout, generator: &generator)
                : []
        )
    }

    private static func makeLengths(
        for workout: ImportedWorkout,
        generator: inout DeterministicGenerator
    ) -> [SwimLengthPoint] {
        let count = max(Int((workout.distanceMeters ?? 0) / 25), 1)
        var clock = workout.startDate

        return (1...count).map { index in
            let rested = index > 1 && index % 4 == 1
            let seconds = (30 + generator.value(in: -2...4)).rounded()

            if rested { clock.addTimeInterval(20) }
            let start = clock
            clock.addTimeInterval(seconds)

            return SwimLengthPoint(
                index: index,
                start: start,
                seconds: seconds,
                meters: 25,
                followedRest: rested
            )
        }
    }

    private static func makeDailySteps(
        days: Int,
        endingAt today: Date,
        calendar: Calendar,
        generator: inout DeterministicGenerator
    ) -> [SamplePoint] {
        (0..<days).reversed().compactMap { offset -> SamplePoint? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let weekend = calendar.isDateInWeekend(date)
            let steps = generator.value(in: weekend ? 3_000.0...7_000.0 : 6_500.0...13_000.0)
            return SamplePoint(date: date, value: steps.rounded())
        }
    }

    private static func makeHourlySteps(
        on today: Date,
        calendar: Calendar,
        generator: inout DeterministicGenerator
    ) -> [SamplePoint] {
        (0..<24).compactMap { hour -> SamplePoint? in
            guard let date = calendar.date(byAdding: .hour, value: hour, to: today) else { return nil }
            let steps: Double = switch hour {
            case 0..<6: generator.value(in: 0.0...40.0)
            case 7, 8: generator.value(in: 900.0...1_600.0)
            case 12, 13: generator.value(in: 600.0...1_100.0)
            case 18, 19: generator.value(in: 700.0...1_400.0)
            default: generator.value(in: 120.0...520.0)
            }
            return SamplePoint(date: date, value: steps.rounded())
        }
    }
}
#endif
