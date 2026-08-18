import SwiftData
import SwiftUI

/// Everything onboarding asked, available to change afterwards.
///
/// Edits are recorded immediately but never rewrite history: they shape the
/// weeks still to come. Anything that would change work already prescribed is
/// behind an explicit action.
struct TrainingProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: AthleteProfile
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    @State private var message: String?
    @State private var isConfirmingReassessment = false
    @State private var customPool = ""

    private var setup: AthleteSetup { profile.setup ?? AthleteSetup() }

    var body: some View {
        List {
            goalSection
            baselineSection
            daysSection
            sportsSection
            poolSection
            planSection
        }
        .navigationTitle("Training Profile")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Training Profile", isPresented: showingMessage) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            "Rebuild the days still ahead?",
            isPresented: $isConfirmingReassessment,
            titleVisibility: .visible
        ) {
            Button("Rebuild upcoming days") { reassess() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sessions you have reported on or skipped stay exactly as they are. Only days still to come are rebuilt, using what you can do now.")
        }
    }

    // MARK: - Sections

    private var goalSection: some View {
        Section {
            Picker("Goal", selection: binding(\.goal)) {
                ForEach(TrainingGoal.allCases, id: \.self) { goal in
                    Text(goal.displayName).tag(goal)
                }
            }
        } header: {
            Text("Goal")
        } footer: {
            Text(setup.goal.detail)
        }
    }

    private var baselineSection: some View {
        Section {
            Picker("Running", selection: binding(\.baseline.running)) {
                ForEach(RunningBaseline.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Swimming", selection: binding(\.baseline.swimming)) {
                ForEach(SwimmingBaseline.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Stroke", selection: binding(\.baseline.stroke)) {
                ForEach(SwimStroke.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Cycling", selection: binding(\.baseline.cycling)) {
                ForEach(CyclingBaseline.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            LabeledContent("Started", value: profile.trainingStartDate.formatted(date: .abbreviated, time: .omitted))
        } header: {
            Text("What you can do")
        } footer: {
            Text("Changing these does not alter the weeks you have already trained, and does not change the week you are on until you rebuild it below.")
        }
    }

    private var daysSection: some View {
        Section {
            ForEach(Weekday.trainingWeek, id: \.self) { weekday in
                Toggle(weekday.displayName, isOn: dayBinding(weekday))
            }
        } header: {
            Text("Training days")
        } footer: {
            Text(setup.schedule.isUsable
                 ? "Days you do not pick become recovery days."
                 : "Pick at least two days.")
        }
    }

    private var sportsSection: some View {
        Section {
            ForEach(preferences, id: \.sport) { preference in
                Picker(preference.sport.displayName, selection: sessionsBinding(preference.sport)) {
                    Text("Not yet").tag(0)
                    ForEach(1...SportPreference.permittedSessions.upperBound, id: \.self) {
                        Text("\($0) × week").tag($0)
                    }
                }
            }
        } header: {
            Text("How often")
        } footer: {
            Text("A starting point, not a promise. TriLoop schedules fewer sessions when a week cannot hold them.")
        }
    }

    private var poolSection: some View {
        Section {
            Picker("Pool length", selection: poolBinding) {
                Text("25 m").tag(25.0)
                Text("50 m").tag(50.0)
                if !isStandardPool { Text("\(Int(profile.poolLengthMeters)) m").tag(profile.poolLengthMeters) }
            }
        } header: {
            Text("Swimming")
        } footer: {
            Text("Sets are built in whole lengths, so this decides how your swims are written.")
        }
    }

    private var planSection: some View {
        Section {
            Button("Update upcoming days") { reshape() }
                .disabled(plans.currentPlan() == nil)

            Button("Rebuild from what I can do now") { isConfirmingReassessment = true }
                .disabled(plans.currentPlan() == nil)
        } header: {
            Text("Plan")
        } footer: {
            Text("Updating moves the sports still ahead onto days you can train. Rebuilding also recalculates how hard those sessions are.")
        }
    }

    // MARK: - Bindings

    private var preferences: [SportPreference] {
        setup.preferences.isEmpty ? SportPreference.defaults(for: setup.baseline) : setup.preferences
    }

    private var isStandardPool: Bool {
        profile.poolLengthMeters == 25 || profile.poolLengthMeters == 50
    }

    private func binding<Value>(_ path: WritableKeyPath<AthleteSetup, Value>) -> Binding<Value> {
        Binding(
            get: { setup[keyPath: path] },
            set: { value in update { $0[keyPath: path] = value } }
        )
    }

    private func dayBinding(_ weekday: Weekday) -> Binding<Bool> {
        Binding(
            get: { setup.schedule.isAvailable(on: weekday) },
            set: { isOn in
                update { current in
                    var days = current.schedule.days
                    guard let index = days.firstIndex(where: { $0.weekday == weekday }) else { return }
                    days[index].isAvailable = isOn
                    current.schedule = AthleteSchedule(days: days)
                }
            }
        )
    }

    private func sessionsBinding(_ sport: Sport) -> Binding<Int> {
        Binding(
            get: { preferences.first { $0.sport == sport }?.sessionsPerWeek ?? 0 },
            set: { count in
                update { current in
                    var updated = current.preferences.isEmpty
                        ? SportPreference.defaults(for: current.baseline)
                        : current.preferences
                    guard let index = updated.firstIndex(where: { $0.sport == sport }) else { return }
                    updated[index].sessionsPerWeek = count
                    current.preferences = updated
                }
            }
        )
    }

    private var poolBinding: Binding<Double> {
        Binding(
            get: { profile.poolLengthMeters },
            set: { meters in
                guard PoolLength.isValid(meters) else { return }
                profile.poolLengthMeters = meters
                save()
            }
        )
    }

    // MARK: - Actions

    private func update(_ change: (inout AthleteSetup) -> Void) {
        var current = setup
        change(&current)
        profile.setup = current
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            message = "Could not save your changes: \(error.localizedDescription)"
        }
    }

    private func reshape() {
        guard let plan = plans.currentPlan() else { return }
        let outcome = PlanStore(context: modelContext).reshapeWeek(plan)

        var summary = outcome.isUnchanged
            ? "The days ahead already match your schedule."
            : "\(outcome.changes.count) day\(outcome.changes.count == 1 ? "" : "s") updated."

        if outcome.dropped > 0 {
            summary += " \(outcome.dropped) session\(outcome.dropped == 1 ? "" : "s") no longer fit."
        }
        message = summary
    }

    private func reassess() {
        guard let plan = plans.currentPlan() else { return }

        let parameters = StartingParameterResolver().resolve(
            baseline: setup.baseline,
            goal: setup.goal,
            poolLengthMeters: profile.poolLengthMeters
        )
        let rebuilt = PlanStore(context: modelContext).reapplyParameters(parameters, to: plan)

        message = rebuilt == 0
            ? "Nothing ahead to rebuild this week."
            : "\(rebuilt) day\(rebuilt == 1 ? "" : "s") rebuilt from your current ability."
    }

    private var showingMessage: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }
}
