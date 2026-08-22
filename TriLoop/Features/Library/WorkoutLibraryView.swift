import SwiftData
import SwiftUI

/// Browse the sessions TriLoop ships with, and the athlete's own.
///
/// §10.2: reusable training the athlete can reach for, separate from the week
/// the engine decided.
struct WorkoutLibraryView: View {
    @Query(sort: \StoredWorkoutTemplate.updatedAt, order: .reverse) private var stored: [StoredWorkoutTemplate]
    @State private var sport: Sport = .running

    var body: some View {
        List {
            Section {
                Picker("Sport", selection: $sport) {
                    ForEach(Sport.allCases, id: \.self) { sport in
                        Text(sport.displayName).tag(sport)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if !mine.isEmpty {
                Section("My Workouts") {
                    ForEach(mine) { template in
                        row(template)
                    }
                }
            }

            Section("TriLoop Workouts") {
                ForEach(WorkoutLibrary.templates(for: sport)) { template in
                    row(template)
                }
            }
        }
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var mine: [WorkoutTemplate] {
        stored.map(\.template).filter { $0.sport == sport }
    }

    private func row(_ template: WorkoutTemplate) -> some View {
        NavigationLink {
            WorkoutTemplateDetailView(template: template)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.body.weight(.medium))

                Text(subtitle(template))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(_ template: WorkoutTemplate) -> String {
        var parts = [template.category.displayName]
        if let seconds = template.totalDurationSeconds {
            parts.append(TrainingFormatter.totalDuration(seconds: seconds))
        } else if let meters = template.totalDistanceMeters {
            parts.append(TrainingFormatter.distance(meters: meters))
        }
        if let effort = TodayEffort.text(for: template.targetRPE) {
            parts.append(effort)
        }
        return parts.joined(separator: " · ")
    }
}

/// A reusable workout, shown with the same language as Workout Detail.
struct WorkoutTemplateDetailView: View {
    let template: WorkoutTemplate

    @Query(sort: \WeeklyPlan.startDate, order: .reverse) private var plans: [WeeklyPlan]
    @State private var isAddingToPlan = false
    /// Built once. A computed property would mint new model objects on every
    /// body evaluation.
    @State private var preview: PlannedWorkout?

    /// §10.3.12: previewed by instantiating it, so what is shown is exactly what
    /// adding it would produce rather than a second rendering of the same idea.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.sport.displayName.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)

                    Text(template.name)
                        .font(.largeTitle.weight(.semibold))

                    if !template.purpose.isEmpty {
                        Text(template.purpose)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 20) {
                    if let seconds = template.totalDurationSeconds {
                        StatTile(value: TrainingFormatter.totalDuration(seconds: seconds), label: "Time")
                    }
                    if let meters = template.totalDistanceMeters {
                        StatTile(value: TrainingFormatter.distance(meters: meters), label: "Distance")
                    }
                    if let range = template.targetRPE {
                        StatTile(value: TrainingFormatter.rpe(range), label: "Effort")
                    }
                    Spacer(minLength: 0)
                }

                if let preview {
                    WorkoutPrescriptionView(workout: preview)
                }

                Button("Add to Plan") { isAddingToPlan = true }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(plans.currentPlan() == nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if preview == nil {
                preview = WorkoutTemplateScheduler.workout(from: template, on: .now)
            }
        }
        .sheet(isPresented: $isAddingToPlan) {
            if let plan = plans.currentPlan() {
                AddToPlanSheet(template: template, plan: plan)
            }
        }
    }
}

/// Choosing the day, and saying plainly what is already on it.
///
/// §10.2.9: a generated session is never replaced unless the athlete asks.
struct AddToPlanSheet: View {
    let template: WorkoutTemplate
    let plan: WeeklyPlan

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var date: Date = .now
    @State private var failure: String?

    private var conflict: WorkoutTemplateScheduler.Conflict {
        WorkoutTemplateScheduler.conflict(on: date, in: plan)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker(
                        "Day",
                        selection: $date,
                        in: plan.startDate...plan.endDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                } header: {
                    Text("When")
                }

                Section {
                    switch conflict {
                    case .none:
                        Text("Nothing else is planned for this day.")
                            .foregroundStyle(.secondary)

                        Button("Add \(template.name)") { add(resolving: .alongside) }

                    case .session(_, let title):
                        Text("\(title) is already planned for this day.")
                            .foregroundStyle(.secondary)

                        Button("Add alongside \(title)") { add(resolving: .alongside) }
                        Button("Replace \(title)", role: .destructive) { add(resolving: .replace) }

                    case .completedSession(_, let title):
                        Text("You have already trained \(title) on this day.")
                            .foregroundStyle(.secondary)

                        Button("Add alongside it") { add(resolving: .alongside) }
                    }
                } header: {
                    Text("This day")
                } footer: {
                    Text("Workouts you add are training you chose to do. They are not counted as part of the plan TriLoop set you.")
                }
            }
            .navigationTitle("Add to Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Could not add", isPresented: showingFailure) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
            .task { date = max(plan.startDate, min(.now, plan.endDate)) }
        }
    }

    private var showingFailure: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    private func add(resolving resolution: WorkoutTemplateScheduler.Resolution) {
        do {
            try WorkoutTemplateScheduler.add(
                template,
                to: plan,
                on: date,
                resolving: resolution
            )
            try modelContext.save()
            // The week just changed, so the Watch is out of date until this runs.
            Task { await WatchScheduleSync.sync(plan) }
            dismiss()
        } catch WorkoutTemplateScheduler.Failure.dateOutsidePlan {
            failure = "That day is not part of this training week."
        } catch WorkoutTemplateScheduler.Failure.cannotReplaceCompletedSession {
            failure = "That session has already been trained, so it cannot be replaced."
        } catch {
            failure = "The workout could not be added."
        }
    }
}
