import SwiftData
import SwiftUI

struct PlanView: View {
    @Query(sort: \WeeklyPlan.startDate, order: .reverse) private var plans: [WeeklyPlan]

    @Environment(\.modelContext) private var modelContext
    @State private var selectedPlanID: UUID?
    @State private var reshapeMessage: String?

    private var selectedPlan: WeeklyPlan? {
        plans.first { $0.id == selectedPlanID } ?? plans.currentPlan()
    }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = selectedPlan {
                    planList(plan)
                } else {
                    ContentUnavailableView(
                        "No plan yet",
                        systemImage: "calendar",
                        description: Text("Your first training week has not been generated.")
                    )
                }
            }
            .navigationTitle(selectedPlan.map { "Week \($0.weekNumber)" } ?? "Plan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let plan = selectedPlan {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if plans.count > 1 {
                                Picker("Week", selection: weekSelection(default: plan.id)) {
                                    ForEach(plans.sorted { $0.weekNumber < $1.weekNumber }, id: \.id) { option in
                                        Text("Week \(option.weekNumber)").tag(option.id)
                                    }
                                }
                            }
                            Button("Update to current schedule") {
                                reshapeMessage = message(
                                    for: PlanStore(context: modelContext).reshapeWeek(plan)
                                )
                            }
                        } label: {
                            Label("Week options", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("Plan", isPresented: showingReshapeMessage) {
                Button("OK", role: .cancel) { reshapeMessage = nil }
            } message: {
                Text(reshapeMessage ?? "")
            }
        }
    }

    private var showingReshapeMessage: Binding<Bool> {
        Binding(get: { reshapeMessage != nil }, set: { if !$0 { reshapeMessage = nil } })
    }

    private func message(for changed: Int) -> String {
        switch changed {
        case 0: "This week already matches your schedule."
        case 1: "One day updated. Reported sessions were left alone."
        default: "\(changed) days updated. Reported sessions were left alone."
        }
    }

    private func weekSelection(default id: UUID) -> Binding<UUID> {
        Binding(
            get: { selectedPlanID ?? id },
            set: { selectedPlanID = $0 }
        )
    }

    private func planList(_ plan: WeeklyPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(TrainingFormatter.weekRange(start: plan.startDate, end: plan.endDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Card(padding: 4) {
                    VStack(spacing: 0) {
                        ForEach(plan.orderedWorkouts, id: \.id) { workout in
                            NavigationLink {
                                WorkoutDetailView(workout: workout)
                            } label: {
                                WorkoutRow(
                                    workout: workout,
                                    isToday: Calendar.current.isDateInToday(workout.date)
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)

                            if workout.id != plan.orderedWorkouts.last?.id {
                                Divider().padding(.leading, 10)
                            }
                        }
                    }
                }

                Card {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(
                            plan.generationReason.isEmpty
                                ? "Plan adapts based on your performance, recovery and feedback."
                                : plan.generationReason
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}

#Preview {
    PlanView()
        .modelContainer(PreviewData.container)
}
