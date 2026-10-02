import SwiftUI

/// Sport-specific sensor readings from a completed session.
///
/// Every row is optional and the whole section shortens when evidence is absent.
/// Phone-recorded routes are shown here alongside the speed derived from GPS.
struct AdvancedMetricsView: View {
    let metrics: RecordedMetrics
    let sport: Sport?
    var summary: ImportedWorkoutSummary? = nil
    var route: [RecordedRoutePoint] = []

    private var rows: [(name: String, value: String)] {
        var result: [(String, String)] = []

        switch sport {
        case .running:
            append(&result, "Cadence", metrics.averageCadence) { "\(Int($0.rounded())) spm" }
            append(&result, "Speed", metrics.averageRunningSpeed) { pace(fromMetersPerSecond: $0) }
            append(&result, "Power", metrics.averageRunningPower) { "\(Int($0.rounded())) W" }
            append(&result, "Stride length", metrics.averageStrideLength) { String(format: "%.2f m", $0) }
            append(&result, "Ground contact", metrics.averageGroundContactTime) { "\(Int($0.rounded())) ms" }
            append(&result, "Vertical oscillation", metrics.averageVerticalOscillation) { String(format: "%.1f cm", $0) }

        case .cycling:
            append(&result, "Speed", metrics.averageCyclingSpeed) { String(format: "%.1f km/h", $0 * 3.6) }
            append(&result, "Cadence", metrics.averageCyclingCadence) { "\(Int($0.rounded())) rpm" }
            append(&result, "Power", metrics.averageCyclingPower) { "\(Int($0.rounded())) W" }
            append(&result, "FTP", metrics.functionalThresholdPower) { "\(Int($0.rounded())) W" }

        case .swimming:
            if let environment = metrics.swimEnvironment {
                result.append((
                    "Environment",
                    environment == .pool ? "Pool" : "Open water"
                ))
            }

            if let summary {
                if let distance = summary.distanceMeters,
                   distance > 0,
                   summary.duration > 0 {
                    result.append((
                        "Average pace",
                        "\(TrainingFormatter.swimPace(secondsPer100m: summary.duration / (distance / 100))) /100 m"
                    ))
                }

                if let lengths = summary.swimmingLengths, lengths > 0 {
                    result.append(("Lengths", "\(lengths)"))
                }

                if let strokes = summary.swimmingStrokeCount, strokes > 0 {
                    result.append(("Strokes", "\(Int(strokes.rounded()))"))
                }

                if let continuous = summary.longestContinuousSwimMeters, continuous > 0 {
                    result.append((
                        "Longest continuous",
                        TrainingFormatter.distance(meters: continuous)
                    ))
                }

                if let averageHeartRate = summary.averageHeartRate, averageHeartRate > 0 {
                    result.append(("Average heart rate", "\(Int(averageHeartRate.rounded())) bpm"))
                }

                if let maximumHeartRate = summary.maximumHeartRate, maximumHeartRate > 0 {
                    result.append(("Maximum heart rate", "\(Int(maximumHeartRate.rounded())) bpm"))
                }
            }

        case nil:
            break
        }

        if let summary, summary.discipline == .multisport {
            for (index, segment) in metrics.multisportSegments.enumerated() {
                result.append((
                    multisportSegmentName(segment, index: index),
                    multisportSegmentValue(segment)
                ))
            }

            if let lengths = summary.swimmingLengths, lengths > 0 {
                result.append(("Swim lengths", "\(lengths)"))
            }

            if let strokes = summary.swimmingStrokeCount, strokes > 0 {
                result.append(("Swim strokes", "\(Int(strokes.rounded()))"))
            }

            if let continuous = summary.longestContinuousSwimMeters, continuous > 0 {
                result.append((
                    "Longest continuous swim",
                    TrainingFormatter.distance(meters: continuous)
                ))
            }
        }

        if let summary, sport != .swimming {
            if let averageHeartRate = summary.averageHeartRate, averageHeartRate > 0 {
                result.append(("Average heart rate", "\(Int(averageHeartRate.rounded())) bpm"))
            }

            if let maximumHeartRate = summary.maximumHeartRate, maximumHeartRate > 0 {
                result.append(("Maximum heart rate", "\(Int(maximumHeartRate.rounded())) bpm"))
            }
        }

        if let elevation = summary?.elevationAscendedMeters, elevation > 0 {
            result.append(("Elevation gain", "\(Int(elevation.rounded())) m"))
        }

        append(&result, "Active calories", metrics.activeEnergyKilocalories) {
            "\(Int($0.rounded())) kcal"
        }
        append(&result, "Apple effort", metrics.workoutEffort) { "\(Int($0.rounded()))/10" }
        if metrics.workoutEffort == nil {
            append(&result, "Estimated effort", metrics.estimatedWorkoutEffort) { "\(Int($0.rounded()))/10" }
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrow(text: "Recorded detail")

                    ForEach(rows, id: \.name) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(row.name)
                                .font(.subheadline)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(row.value)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }

            WorkoutRouteView(points: route.isEmpty ? metrics.route : route)
        }
    }

    private func multisportSegmentName(
        _ segment: RecordedMultisportSegment,
        index: Int
    ) -> String {
        if segment.isTransition {
            return "Leg \(index + 1) · Transition"
        }

        let name = segment.sport?.discipline.displayName ?? "Activity"
        return "Leg \(index + 1) · \(name)"
    }

    private func multisportSegmentValue(_ segment: RecordedMultisportSegment) -> String {
        var parts: [String] = [
            TrainingFormatter.totalDuration(seconds: segment.durationSeconds)
        ]

        if let distance = segment.distanceMeters, distance > 0 {
            parts.append(TrainingFormatter.distance(meters: distance))

            guard segment.durationSeconds > 0 else {
                return parts.joined(separator: " · ")
            }

            switch segment.sport {
            case .running:
                let secondsPerKm = Int((segment.durationSeconds / (distance / 1_000)).rounded())
                parts.append(String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60))

            case .cycling:
                let speed = distance / segment.durationSeconds * 3.6
                parts.append(String(format: "%.1f km/h", speed))

            case .swimming:
                let pace = segment.durationSeconds / (distance / 100)
                parts.append("\(TrainingFormatter.swimPace(secondsPer100m: pace)) /100 m")

            case nil:
                break
            }
        }

        return parts.joined(separator: " · ")
    }

    private func append(
        _ rows: inout [(String, String)],
        _ name: String,
        _ value: Double?,
        format: (Double) -> String
    ) {
        guard let value, value > 0 else { return }
        rows.append((name, format(value)))
    }

    /// Runners read minutes per kilometre, not metres per second.
    private func pace(fromMetersPerSecond speed: Double) -> String {
        guard speed > 0 else { return "—" }
        let secondsPerKm = Int((1_000 / speed).rounded())
        return String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60)
    }
}
