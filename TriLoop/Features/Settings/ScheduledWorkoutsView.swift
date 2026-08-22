#if DEBUG
import SwiftUI

/// Developer view of what WorkoutKit currently holds, used to tell a scheduling
/// failure apart from a workout simply being queued for a future day.
struct ScheduledWorkoutsView: View {
    let isSupported: Bool
    let authorization: WorkoutSchedulingAuthorization
    let entries: [ScheduledWorkoutSummary]
    let refresh: () async -> Void

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Scheduling", value: isSupported ? "Supported" : "Unavailable")
                LabeledContent("Authorization", value: "\(authorization)")
            }

            Section("Scheduled") {
                if entries.isEmpty {
                    Text("Nothing scheduled.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName ?? "Untitled workout")
                            .font(.subheadline.weight(.medium))
                        Text(entry.date?.formatted(date: .abbreviated, time: .shortened) ?? "No date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Drives Today's "finished, waiting to sync" state.
                        Text(entry.isComplete ? "Marked complete by the Watch" : "Not yet complete")
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
#endif
