import SwiftUI

/// Read-only view of what WorkoutKit currently holds, used to tell a scheduling
/// failure apart from a workout simply being queued for a future day.
struct ScheduledWorkoutsView: View {
    let isSupported: Bool
    let authorization: WorkoutSchedulingAuthorization
    let entries: [ScheduledWorkoutSummary]
    let refresh: () async -> Void

    @StateObject private var watch = WatchAvailability.shared

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Paired Watch available", value: watch.canSchedule ? "Yes" : "No")
                LabeledContent("Time zone", value: TimeZone.current.identifier)
                LabeledContent("Today, unfinished", value: "\(entries.filter { !$0.isComplete && $0.date.map({ Calendar.current.isDateInToday($0) }) == true }.count)")
                LabeledContent("Scheduling", value: isSupported ? "Supported" : "Unavailable")
                LabeledContent("Authorization", value: "\(authorization)")
                LabeledContent("Scheduled", value: "\(entries.count)")
            }

            Section {
                Text("This is the schedule returned by Apple on your iPhone. It does not confirm delivery or visibility on your Watch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Scheduled") {
                if entries.isEmpty {
                    Text("Nothing scheduled.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName ?? "Untitled workout")
                            .font(.subheadline.weight(.medium))
                        Text(entry.date.map { TrainingFormatter.shortDateTime($0) } ?? "No date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Drives Today's "finished, waiting to sync" state.
                        Text(entry.isComplete ? "Marked complete" : "Not yet complete")
                            .font(.caption2)
                            .foregroundStyle(entry.isComplete ? .green : .secondary)
                        Text(entry.id.uuidString)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("Apple Watch schedule")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task { await refresh() }
    }
}
