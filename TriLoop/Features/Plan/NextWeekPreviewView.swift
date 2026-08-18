import SwiftData
import SwiftUI

/// Shows the week the generator *would* produce, before anything is written.
///
/// The plan is built in memory and only persisted when the athlete confirms, so
/// looking at next week never commits them to it.
struct NextWeekPreviewView: View {
    let previousWeek: WeeklyPlan

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var generated = false
    @State private var failure: String?

    private var preview: WeeklyPlan {
        WeeklyPlanGenerator().generate(
            after: previousWeek,
            analysis: WeeklyAnalyser().analyse(previousWeek)
        )
    }

    var body: some View {
        let plan = preview

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(TrainingFormatter.weekRange(start: plan.startDate, end: plan.endDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Based on your Week \(previousWeek.weekNumber) analysis")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.fill.tertiary, in: .capsule)
                    .foregroundStyle(.secondary)

                Card(padding: 4) {
                    VStack(spacing: 0) {
                        ForEach(plan.orderedWorkouts, id: \.id) { workout in
                            WorkoutRow(workout: workout)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)

                            if workout.id != plan.orderedWorkouts.last?.id {
                                Divider().padding(.leading, 10)
                            }
                        }
                    }
                }

                if !plan.generationReason.isEmpty {
                    Text(plan.generationReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    generate()
                } label: {
                    Text(generated ? "Week \(plan.weekNumber) Added" : "Generate Week \(plan.weekNumber)")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(generated)

                Text("You can review and regenerate anytime.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .navigationTitle("Week \(plan.weekNumber) Preview")
        .navigationBarTitleDisplayMode(.large)
        .alert("Week not created", isPresented: showingFailure) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private func generate() {
        do {
            try PlanStore(context: modelContext).generateNextWeek(after: previousWeek)
            generated = true
            dismiss()
        } catch {
            failure = "Could not create the week: \(error.localizedDescription)"
        }
    }

    private var showingFailure: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }
}
