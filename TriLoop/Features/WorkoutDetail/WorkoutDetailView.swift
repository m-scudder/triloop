import SwiftData
import SwiftUI

/// Pushed presentation of a single session.
///
/// The content itself lives in `WorkoutDayDetail` so the Plan tab can show the
/// same thing inline without the two drifting apart.
struct WorkoutDetailView: View {
    let workout: PlannedWorkout
    var scheduler: any WorkoutScheduling = WorkoutKitScheduler()

    var body: some View {
        WorkoutDayDetail(workout: workout, scheduler: scheduler)
            .navigationTitle(workout.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct LabeledSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        WorkoutDetailView(workout: PreviewData.workout(.running))
    }
    .modelContainer(PreviewData.container)
}
#endif
