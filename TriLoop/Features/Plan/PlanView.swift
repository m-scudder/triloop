import SwiftData
import SwiftUI

struct PlanView: View {
    @Query(sort: \WeeklyPlan.startDate, order: .reverse) private var plans: [WeeklyPlan]

    var body: some View {
        NavigationStack {
            Group {
                if let plan = plans.currentPlan() {
                    planList(plan)
                } else {
                    ContentUnavailableView(
                        "No plan yet",
                        systemImage: "calendar",
                        description: Text("Your first training week has not been generated.")
                    )
                }
            }
            .navigationTitle("Plan")
        }
    }

    private func planList(_ plan: WeeklyPlan) -> some View {
        List {
            Section {
                ForEach(plan.orderedWorkouts, id: \.id) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        WorkoutRow(workout: workout, isToday: Calendar.current.isDateInToday(workout.date))
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week \(plan.weekNumber)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(TrainingFormatter.weekRange(start: plan.startDate, end: plan.endDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
                .padding(.bottom, 8)
            } footer: {
                if !plan.generationReason.isEmpty {
                    Text(plan.generationReason)
                        .padding(.top, 8)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

#Preview {
    PlanView()
        .modelContainer(PreviewData.container)
}
