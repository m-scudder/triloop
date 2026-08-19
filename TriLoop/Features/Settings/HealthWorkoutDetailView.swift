#if DEBUG
import SwiftData
import SwiftUI

/// One historical workout in the same detail the app gives a planned session.
///
/// Reuses `WorkoutChartsView`, so what is shown here is the production rendering
/// rather than a diagnostic lookalike — if a chart is wrong here, it is wrong in
/// the app too. Still read-only: nothing is imported or attached to a plan.
struct HealthWorkoutDetailView: View {
    let record: HealthWorkoutRecord

    @Environment(\.healthProvider) private var provider
    @Query private var profiles: [AthleteProfile]
    @State private var samples: WorkoutSamples?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                facts
                availability

                if let samples, !samples.isEmpty {
                    WorkoutChartsView(discipline: record.sport?.discipline, samples: samples)

                    if case .success(let breakdown) = HeartRateZoneResolver.breakdown(
                        heartRate: samples.heartRate,
                        birthDate: profiles.first?.setup?.birthDate,
                        // Age-based only. This session's own peak cannot set the
                        // ceiling — that would place every workout in Z5 by
                        // construction — and §16 keeps historical inspection
                        // independent of stored training history.
                        observedMaximum: nil
                    ) {
                        HeartRateZoneView(breakdown: breakdown)
                    }
                } else if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if samples != nil {
                    Text("Health holds no heart rate or pace samples for this session.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(record.activityName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSamples() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.start.formatted(date: .complete, time: .shortened))
                .font(.headline)

            if let source = record.sourceName {
                Text("Recorded by \(source)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !record.isTrainedByTriLoop {
                Text("TriLoop does not train this activity. Everything Health recorded is shown; only pace and cadence are withheld, because they would read as performance in a session that never measured it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: "Recorded")

            fact("Duration", Duration.seconds(record.duration).formatted(.time(pattern: .hourMinute)))
            fact("Distance", record.distanceMeters.map { TrainingFormatter.distance(meters: $0) })
            fact("Average heart rate", record.averageHeartRate.map { "\(Int($0.rounded())) bpm" })
            fact("Active energy", record.energyKilocalories.map { "\(Int($0.rounded())) kcal" })

            if record.sport == .swimming {
                fact("Lengths", record.swimmingLengths.map(String.init))
            }
        }
    }

    /// §20: what Health holds for this one session. Only metrics that could
    /// apply to the activity are listed, so a swim is never shown as missing
    /// cycling power.
    private var availability: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: "HealthKit data")

            ForEach(record.metricPresence) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.isPresent ? "checkmark" : "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.isPresent ? Color.green : Color.secondary)
                        .frame(width: 16)
                    Text(entry.name)
                        .foregroundStyle(entry.isPresent ? .primary : .secondary)
                    Spacer()
                }
                .font(.subheadline)
            }
        }
    }

    /// Absent values say so instead of showing a zero.
    private func fact(_ name: String, _ value: String?) -> some View {
        HStack {
            Text(name)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "Not recorded")
                .foregroundStyle(value == nil ? .secondary : .primary)
        }
        .font(.subheadline)
    }

    private func loadSamples() async {
        guard samples == nil else { return }
        do {
            samples = try await provider.samples(forWorkout: record.id)
        } catch {
            samples = WorkoutSamples()
            failure = "Could not read the detail for this session."
        }
    }
}
#endif
