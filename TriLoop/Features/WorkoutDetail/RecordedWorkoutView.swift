import SwiftUI

/// What was actually recorded, shown beside what was prescribed.
///
/// Every metric is optional because HealthKit may not hold it for a given
/// session. Missing values are omitted rather than shown as zero, which would
/// read as a real measurement.
struct RecordedWorkoutView: View {
    let workout: PlannedWorkout
    let summary: ImportedWorkoutSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: "Recorded")

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 8) {
                        StatTile(
                            value: TrainingFormatter.totalDuration(seconds: summary.duration),
                            label: "Duration"
                        )
                        if let distance = summary.distanceMeters, distance > 0 {
                            StatTile(
                                value: TrainingFormatter.distance(meters: distance),
                                label: "Distance"
                            )
                        }
                        StatTile(
                            value: "\(Int((workout.recordedCompletion * 100).rounded()))%",
                            label: "Of plan"
                        )
                    }

                    if summary.averageHeartRate != nil || summary.elevationAscendedMeters != nil {
                        Divider()

                        HStack(alignment: .top, spacing: 8) {
                            if let average = summary.averageHeartRate {
                                StatTile(value: "\(Int(average.rounded()))", label: "Avg bpm")
                            }
                            if let maximum = summary.maximumHeartRate {
                                StatTile(value: "\(Int(maximum.rounded()))", label: "Max bpm")
                            }
                            if let elevation = summary.elevationAscendedMeters {
                                StatTile(
                                    value: TrainingFormatter.distance(meters: elevation),
                                    label: "Ascent"
                                )
                            }
                        }
                    }

                    if summary.swimmingLengths != nil || summary.longestContinuousSwimMeters != nil {
                        Divider()

                        HStack(alignment: .top, spacing: 8) {
                            if let lengths = summary.swimmingLengths {
                                StatTile(value: "\(lengths)", label: "Lengths")
                            }
                            if let continuous = summary.longestContinuousSwimMeters {
                                StatTile(
                                    value: TrainingFormatter.distance(meters: continuous),
                                    label: "Longest non-stop"
                                )
                            }
                            if let strokes = summary.swimmingStrokeCount {
                                StatTile(value: "\(Int(strokes.rounded()))", label: "Strokes")
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.startDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                        Text(sourceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sourceName: String {
        guard let source = summary.source else { return "Imported from Apple Health" }
        return source == "com.apple.workout"
            ? "Apple Workout · imported from Health"
            : "\(source) · imported from Health"
    }
}
