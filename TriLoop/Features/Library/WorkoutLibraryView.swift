import SwiftData
import SwiftUI

/// Browse the sessions TriLoop ships with, and the athlete's own.
///
/// §10.2: reusable training the athlete can reach for, separate from the week
/// the engine decided.
struct WorkoutLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredWorkoutTemplate.updatedAt, order: .reverse) private var stored: [StoredWorkoutTemplate]
    @State private var sport: Sport = .running
    @State private var isShowingCustomWorkoutExplainer = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Workouts")
                        .font(.headline)

                    Text("Build your own run, ride, or swim and add it to your training week.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("How it works") {
                        isShowingCustomWorkoutExplainer = true
                    }
                    .font(.subheadline.weight(.medium))
                }
                .padding(.vertical, 4)
            }

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
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) { delete(template) }
                            }
                            .contextMenu {
                                Button("Duplicate") { duplicate(template) }
                                Button("Delete", role: .destructive) { delete(template) }
                            }
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
        .sheet(isPresented: $isShowingCustomWorkoutExplainer) {
            CustomWorkoutExplainerView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WorkoutBuilderView(draft: WorkoutDraft(sport: sport))
                } label: {
                    Label("Create workout", systemImage: "plus")
                }
            }
        }
    }

    private var mine: [WorkoutTemplate] {
        stored.map(\.template).filter { $0.sport == sport }
    }

    /// §10.3.16: removing a template never touches the training it produced,
    /// because a planned workout holds its own resolved prescription.
    private func delete(_ template: WorkoutTemplate) {
        guard let row = stored.first(where: { $0.id == template.id }) else { return }
        modelContext.delete(row)
        try? modelContext.save()
    }

    /// A new identity, so editing the copy leaves the original alone.
    private func duplicate(_ template: WorkoutTemplate) {
        let copy = WorkoutTemplate(
            sport: template.sport,
            name: "\(template.name) copy",
            category: template.category,
            purpose: template.purpose,
            structure: template.structure,
            targetRPE: template.targetRPE
        )
        modelContext.insert(StoredWorkoutTemplate(copy))
        try? modelContext.save()
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

private struct CustomWorkoutExplainerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Build your own workout")
                            .font(.title2.weight(.semibold))

                        Text("Create a run, ride, or swim that fits what you want to do, then add it to your current training week.")
                            .foregroundStyle(.secondary)
                    }

                    ExplainerStep(
                        number: 1,
                        title: "Build it",
                        detail: "Choose a sport and combine warm-up, work, recovery, repeat, and cool-down blocks."
                    )
                    ExplainerStep(
                        number: 2,
                        title: "Add it to your plan",
                        detail: "Pick a day. If another session is already planned, you can add yours alongside it or replace the uncompleted session."
                    )
                    ExplainerStep(
                        number: 3,
                        title: "Train it normally",
                        detail: "It appears in Today and works with workout tracking, Apple Watch, Health imports, and post-workout feedback."
                    )
                    ExplainerStep(
                        number: 4,
                        title: "Reuse it anytime",
                        detail: "Saved workouts stay in My Workouts, so you can add them again in future weeks."
                    )

                    Text("Custom workouts are sessions you choose yourself. They are kept separate from the training TriLoop prescribed for you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Custom Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ExplainerStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\\(number)")
                .font(.subheadline.weight(.semibold))
                .frame(width: 28, height: 28)
                .background(.fill.tertiary, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
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
                        if template.source == .triLoop {
                            HStack {
                                Text(template.category.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                InfoButton(title: template.name, explanation: template.purpose)
                            }
                        } else {
                            Text(template.purpose)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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

                NavigationLink {
                    // §10.3.14: a built-in is cloned, never edited in place.
                    WorkoutBuilderView(
                        draft: template.source.isEditable
                            ? WorkoutDraft(editing: template)
                            : WorkoutDraft(customising: template),
                        isNew: !template.source.isEditable
                    )
                } label: {
                    Text(template.source.isEditable ? "Edit" : "Customise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())
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
        } catch let error as PlanReshaper.Failure {
            failure = error.localizedDescription
        } catch {
            failure = "The workout could not be added."
        }
    }
}
