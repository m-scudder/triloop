import SwiftData
import SwiftUI

/// The athlete-facing training profile.
///
/// The overview stays compact and readable. Editing is pushed into focused
/// screens so the profile does not become a second Settings page. Changes save
/// immediately, while applying training-impacting edits to the current week
/// remains explicit.
struct TrainingProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: AthleteProfile
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    @State private var message: String?
    @State private var isConfirmingReassessment = false

    /// Snapshot from when this profile screen opened. It lets TriLoop explain
    /// which edits can change future training without rewriting history.
    @State private var opened: AthleteSetup?

    private var setup: AthleteSetup { profile.setup ?? AthleteSetup() }

    var body: some View {
        List {
            identitySection
            impactSection
            trainingSection
            preferencesSection
            planSection
        }
        .navigationTitle("Training Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if opened == nil { opened = setup }
        }
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

    // MARK: - Overview

    private var identitySection: some View {
        Section {
            NavigationLink {
                identityEditor
            } label: {
                HStack(spacing: 14) {
                    profileAvatar

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profileDisplayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            Text(profile.experienceLevel.displayName)

                            if !trainedSports.isEmpty {
                                Text("·")
                                Text(trainedSports)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                .padding(.vertical, 6)
            }
            .accessibilityLabel("Athlete details, \(profileDisplayName)")
        }
    }

    @ViewBuilder
    private var impactSection: some View {
        let impact = pendingImpact
        if impact.isTrainingImpacting {
            Section {
                Label("Upcoming training needs review", systemImage: "info.circle")
                    .font(.subheadline.weight(.medium))

                Text(impact.reasons.map(\.displayName).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Your completed and reported workouts stay unchanged. Use the Plan actions below when you want these edits applied to the days still ahead.")
            }
        }
    }

    private var trainingSection: some View {
        Section("Training") {
            NavigationLink {
                goalEditor
            } label: {
                ProfileNavigationRow(
                    title: "Goal",
                    systemImage: "scope",
                    value: setup.goal.displayName
                )
            }

            NavigationLink {
                abilityEditor
            } label: {
                ProfileNavigationRow(
                    title: "Current ability",
                    systemImage: "gauge.with.dots.needle.33percent",
                    value: profile.experienceLevel.displayName
                )
            }

            NavigationLink {
                availabilityEditor
            } label: {
                TrainingDaysSummaryRow(schedule: setup.schedule)
            }

            NavigationLink {
                trainingMixEditor
            } label: {
                ProfileNavigationRow(
                    title: "Training mix",
                    systemImage: "chart.bar.xaxis",
                    value: trainingMixSummary
                )
            }

            if swimmingPreference?.isTrained == true {
                NavigationLink {
                    swimmingEditor
                } label: {
                    ProfileNavigationRow(
                        title: "Swimming",
                        systemImage: "figure.pool.swim",
                        value: "\(Int(profile.poolLengthMeters)) m pool"
                    )
                }
            }
        }
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            NavigationLink {
                heartRateEditor
            } label: {
                ProfileNavigationRow(
                    title: "Heart-rate zones",
                    systemImage: "heart.text.square",
                    value: setup.birthDate == nil ? "Workout-based" : "Age + workouts"
                )
            }

            Picker("Units", selection: unitsBinding) {
                Text("Metric").tag(true)
                Text("Imperial").tag(false)
            }
        }
    }

    private var planSection: some View {
        Section {
            Button("Update upcoming days") { reshape() }
                .disabled(plans.currentPlan() == nil)

            Button("Rebuild from what I can do now") {
                isConfirmingReassessment = true
            }
            .disabled(plans.currentPlan() == nil)
        } header: {
            Text("Plan")
        } footer: {
            Text("Update moves sessions still ahead onto days you can train. Rebuild also recalculates those sessions from your current ability.")
        }
    }

    private var pendingImpact: ProfileEditImpact {
        guard let opened else { return .safe }
        return AthleteProfileEditor.impact(from: opened, to: setup)
    }

    // MARK: - Focused editors

    private var identityEditor: some View {
        Form {
            Section("Athlete") {
                TextField("Name (optional)", text: nameBinding)
                    .textInputAutocapitalization(.words)

                LabeledContent("Level", value: profile.experienceLevel.displayName)

                if !trainedSports.isEmpty {
                    LabeledContent("Sports", value: trainedSports)
                }

                LabeledContent(
                    "Training since",
                    value: profile.trainingStartDate.formatted(date: .abbreviated, time: .omitted)
                )
            }
        }
        .navigationTitle("Athlete")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var goalEditor: some View {
        Form {
            Section {
                Picker("Goal", selection: binding(\.goal)) {
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        Text(goal.displayName).tag(goal)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("What are you training for?")
            } footer: {
                Text(setup.goal.detail)
            }
        }
        .navigationTitle("Goal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var abilityEditor: some View {
        Form {
            Section("Running") {
                Picker("Running", selection: binding(\.baseline.running)) {
                    ForEach(RunningBaseline.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }

            Section("Swimming") {
                Picker("Swimming", selection: binding(\.baseline.swimming)) {
                    ForEach(SwimmingBaseline.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }

                Picker("Stroke", selection: binding(\.baseline.stroke)) {
                    ForEach(SwimStroke.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
            }

            Section("Cycling") {
                Picker("Cycling", selection: binding(\.baseline.cycling)) {
                    ForEach(CyclingBaseline.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("Current Ability")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availabilityEditor: some View {
        Form {
            Section {
                ForEach(Weekday.trainingWeek, id: \.self) { weekday in
                    Toggle(weekday.displayName, isOn: dayBinding(weekday))
                }
            } header: {
                Text("Days you can train")
            } footer: {
                if setup.schedule.isUsable {
                    Text("TriLoop fits your sessions onto these days and keeps recovery between harder efforts.")
                } else {
                    Text("Choose at least two days so TriLoop can build a usable week.")
                }
            }
        }
        .navigationTitle("Training Days")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trainingMixEditor: some View {
        Form {
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
                Text("Sessions per week")
            } footer: {
                Text("This is your preferred mix. TriLoop may schedule fewer sessions when your available days or recovery needs require it.")
            }
        }
        .navigationTitle("Training Mix")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var swimmingEditor: some View {
        Form {
            Section {
                Picker("Pool length", selection: poolBinding) {
                    Text("25 m").tag(25.0)
                    Text("50 m").tag(50.0)

                    if !isStandardPool {
                        Text("\(Int(profile.poolLengthMeters)) m").tag(profile.poolLengthMeters)
                    }
                }
            } footer: {
                Text("Pool length is used to turn swim distances into lengths and to interpret completed sessions.")
            }
        }
        .navigationTitle("Swimming")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heartRateEditor: some View {
        Form {
            Section {
                Toggle("Use my age for zones", isOn: usesBirthDate)

                if setup.birthDate != nil {
                    DatePicker(
                        "Date of birth",
                        selection: birthDateBinding,
                        in: birthDateRange,
                        displayedComponents: .date
                    )
                }
            } header: {
                Text("Heart-rate zones")
            } footer: {
                Text(zoneFooter)
            }
        }
        .navigationTitle("Heart-rate Zones")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Overview values

    private var profileAvatar: some View {
        Group {
            if let monogram {
                Text(monogram)
                    .font(.headline.weight(.semibold))
            } else {
                Image(systemName: "person.fill")
                    .font(.headline)
            }
        }
        .foregroundStyle(.primary)
        .frame(width: 52, height: 52)
        .background(.fill.tertiary, in: .circle)
    }

    private var profileDisplayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Athlete" : trimmed
    }

    private var monogram: String? {
        guard let first = profile.name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }

    private var trainedSports: String {
        preferences
            .filter(\.isTrained)
            .map { $0.sport.displayName }
            .joined(separator: " · ")
    }

    private var trainingMixSummary: String {
        let trained = preferences.filter(\.isTrained)
        guard !trained.isEmpty else { return "Not set" }

        return trained
            .map { "\($0.sessionsPerWeek) \(shortSportName($0.sport))" }
            .joined(separator: " · ")
    }

    private func shortSportName(_ sport: Sport) -> String {
        switch sport {
        case .running: "run"
        case .swimming: "swim"
        case .cycling: "ride"
        }
    }

    private var swimmingPreference: SportPreference? {
        preferences.first { $0.sport == .swimming }
    }

    private var preferences: [SportPreference] {
        setup.preferences.isEmpty
            ? SportPreference.defaults(for: setup.baseline)
            : setup.preferences
    }

    private var isStandardPool: Bool {
        profile.poolLengthMeters == 25 || profile.poolLengthMeters == 50
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { profile.name },
            set: { profile.name = $0; save() }
        )
    }

    private var unitsBinding: Binding<Bool> {
        Binding(
            get: { profile.usesMetricUnits },
            set: { profile.usesMetricUnits = $0; save() }
        )
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
                    var days = Weekday.trainingWeek.map { current.schedule.availability(on: $0) }
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

    private var usesBirthDate: Binding<Bool> {
        Binding(
            get: { setup.birthDate != nil },
            set: { isOn in
                var updated = setup
                updated.birthDate = isOn
                    ? Calendar.current.date(byAdding: .year, value: -30, to: .now)
                    : nil
                profile.setup = updated
                save()
            }
        )
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { setup.birthDate ?? .now },
            set: { date in
                var updated = setup
                updated.birthDate = date
                profile.setup = updated
                save()
            }
        )
    }

    private var birthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let oldest = calendar.date(byAdding: .year, value: -100, to: .now) ?? .now
        let youngest = calendar.date(byAdding: .year, value: -10, to: .now) ?? .now
        return oldest...youngest
    }

    private var zoneFooter: String {
        guard let birthDate = setup.birthDate,
              let maximum = HeartRateCeiling.ageBased(birthDate: birthDate, asOf: .now) else {
            return "Without a date of birth, zones become available once you record a hard effort TriLoop can measure against."
        }

        return "Estimated maximum \(Int(maximum)) bpm. If you record a harder effort, TriLoop uses what you actually did."
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

        do {
            let outcome = try PlanStore(context: modelContext).reshapeWeek(plan)

            var summary = outcome.isUnchanged
                ? "The days ahead already match your schedule."
                : "\(outcome.changes.count) day\(outcome.changes.count == 1 ? "" : "s") updated."

            if outcome.dropped > 0 {
                summary += " \(outcome.dropped) session\(outcome.dropped == 1 ? "" : "s") no longer fit."
            }

            opened = setup
            message = summary
        } catch {
            message = "Could not update your week: \(error.localizedDescription)"
        }
    }

    private func reassess() {
        guard let plan = plans.currentPlan() else { return }

        do {
            let rebuilt = try PlanStore(context: modelContext).reassess(
                plan,
                poolLengthMeters: profile.poolLengthMeters
            )

            opened = setup
            message = rebuilt == 0
                ? "Nothing ahead to rebuild this week."
                : "\(rebuilt) day\(rebuilt == 1 ? "" : "s") rebuilt from your current ability."
        } catch {
            message = "Could not rebuild your week: \(error.localizedDescription)"
        }
    }

    private var showingMessage: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )
    }
}

private struct ProfileNavigationRow: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

private struct TrainingDaysSummaryRow: View {
    let schedule: AthleteSchedule

    var body: some View {
        HStack(spacing: 12) {
            Label("Training days", systemImage: "calendar")
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(Weekday.trainingWeek, id: \.self) { weekday in
                    Text(weekday.initial)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(schedule.isAvailable(on: weekday) ? Color.onFocusSurface : Color.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            schedule.isAvailable(on: weekday)
                                ? AnyShapeStyle(Color.focusSurface)
                                : AnyShapeStyle(.fill.tertiary),
                            in: .circle
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(schedule.availableDays.count) training days per week")
        }
    }
}
