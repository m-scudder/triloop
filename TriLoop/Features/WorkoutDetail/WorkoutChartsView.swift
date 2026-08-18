import SwiftUI

/// Two-column grid of a session's metrics, each opening its own chart.
///
/// Stacking full-width charts pushed the rest of the screen a long way down for
/// data that is mostly glanced at; a square card carries the headline figure and
/// the shape, and the detail is one tap away.
struct WorkoutChartsView: View {
    let discipline: Discipline
    let samples: WorkoutSamples
    /// HealthKit's own averages, so the card cannot disagree with the Recorded
    /// block above it.
    var summary: ImportedWorkoutSummary?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var metrics: [WorkoutMetric] {
        WorkoutMetric.all(for: discipline, samples: samples, summary: summary)
    }

    var body: some View {
        if !metrics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Detail")

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(metrics) { metric in
                        NavigationLink {
                            MetricDetailView(metric: metric)
                        } label: {
                            MetricCard(metric: metric)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
