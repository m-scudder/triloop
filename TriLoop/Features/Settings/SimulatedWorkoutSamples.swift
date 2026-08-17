#if DEBUG
import Foundation

/// Synthetic time series for exercising the charts without performing a workout.
///
/// Shapes are deliberately realistic — a warm-up rise, interval spikes, a
/// cooldown — because a flat random series would make a broken chart look fine.
enum SimulatedWorkoutSamples {

    static func make(for workout: PlannedWorkout) -> WorkoutSamples {
        guard let sport = workout.discipline.sport else { return WorkoutSamples() }

        let start = workout.importedSummary?.startDate ?? workout.date
        let minutes = Int(((workout.importedSummary?.duration ?? workout.estimatedDurationSeconds ?? 1800) / 60).rounded())
        guard minutes > 2 else { return WorkoutSamples() }

        return WorkoutSamples(
            heartRate: heartRate(sport: sport, from: start, minutes: minutes),
            cadence: sport == .running ? cadence(from: start, minutes: minutes) : [],
            distancePerMinute: sport == .swimming ? [] : distance(sport: sport, from: start, minutes: minutes),
            swimLengths: sport == .swimming ? lengths(for: workout) : []
        )
    }

    private static func heartRate(sport: Sport, from start: Date, minutes: Int) -> [SamplePoint] {
        let resting: Double = 68
        let ceiling: Double = sport == .running ? 168 : (sport == .cycling ? 152 : 148)

        return (0..<minutes).map { minute in
            let progress = Double(minute) / Double(max(minutes - 1, 1))
            let warmUp = min(progress * 4, 1)
            let coolDown = progress > 0.88 ? (1 - progress) / 0.12 : 1
            // Intervals show as a slow oscillation on top of the drift.
            let interval = sport == .running ? sin(Double(minute) / 1.6) * 7 : sin(Double(minute) / 4) * 3
            let drift = progress * 10

            let value = resting + (ceiling - resting) * warmUp * max(coolDown, 0.35) + interval + drift
            return SamplePoint(
                date: start.addingTimeInterval(Double(minute) * 60),
                value: (value).rounded()
            )
        }
    }

    private static func cadence(from start: Date, minutes: Int) -> [SamplePoint] {
        (0..<minutes).map { minute in
            // Run/walk alternation: running minutes carry a far higher count.
            let running = minute % 3 != 2
            let steps = running ? Double.random(in: 158...168) : Double.random(in: 96...108)
            return SamplePoint(date: start.addingTimeInterval(Double(minute) * 60), value: steps.rounded())
        }
    }

    private static func distance(sport: Sport, from start: Date, minutes: Int) -> [SamplePoint] {
        let perMinute: ClosedRange<Double> = sport == .running ? 120...155 : 260...320

        return (0..<minutes).map { minute in
            let progress = Double(minute) / Double(max(minutes - 1, 1))
            let easing = progress < 0.1 || progress > 0.9 ? 0.55 : 1.0
            return SamplePoint(
                date: start.addingTimeInterval(Double(minute) * 60),
                value: (Double.random(in: perMinute) * easing).rounded()
            )
        }
    }

    private static func lengths(for workout: PlannedWorkout) -> [SwimLengthPoint] {
        let total = workout.importedSummary?.distanceMeters ?? workout.estimatedDistanceMeters ?? 300
        let count = max(Int(total / 25), 1)

        return (1...count).map { index in
            // A rest every fourth length, which is how a beginner set actually runs.
            let rested = index > 1 && index % 4 == 1
            let fatigue = Double(index) / Double(count) * 4
            return SwimLengthPoint(
                index: index,
                seconds: (Double.random(in: 28...34) + fatigue).rounded(),
                meters: 25,
                followedRest: rested
            )
        }
    }
}

/// Hourly steps with a plausible waking shape, so the day chart is not flat.
enum SimulatedDailySteps {
    static func today(calendar: Calendar = .current) -> [SamplePoint] {
        let start = calendar.startOfDay(for: .now)
        let currentHour = calendar.component(.hour, from: .now)

        return (0...currentHour).map { hour in
            let steps: Double = switch hour {
            case 0..<6: Double.random(in: 0...40)
            case 7, 8: Double.random(in: 900...1_600)
            case 12, 13: Double.random(in: 600...1_100)
            case 18, 19: Double.random(in: 700...1_400)
            default: Double.random(in: 120...520)
            }
            return SamplePoint(
                date: calendar.date(byAdding: .hour, value: hour, to: start) ?? start,
                value: steps.rounded()
            )
        }
    }
}
#endif
