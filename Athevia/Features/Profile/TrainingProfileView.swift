import SwiftData
import SwiftUI

/// The athlete-facing training profile.
///
/// The overview stays compact and readable. Editing is pushed into focused
/// screens so the profile does not become a second Settings page. Changes save
/// immediately. Training-impacting edits automatically rebuild only unresolved
/// future workouts; recorded history remains immutable.
struct TrainingProfileView: View {
    @Environment(\.atheviaTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: AthleteProfile
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    @State private var message: String?
    @State private var objectiveDraft: TrainingObjective?
    @State private var newlyAddedSports: Set<Sport> = []
    @State private var isPresentingNewSportAssessment = false
    @State private var trainingMixNeedsUpdate = false

    /// Snapshot from when this profile screen opened. It lets Athevia explain
    /// which edits can change future training without rewriting history.
    @State private var opened: AthleteSetup?

    private var setup: AthleteSetup { profile.setup ?? AthleteSetup() }

    var body: some View {
        List {
            Group {
            identitySection
            historySection
            trainingSection
            preferencesSection
            }
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
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
        .sheet(isPresented: $isPresentingNewSportAssessment) {
            newSportAssessment
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
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        .lineLimit(1)
                    }
                }
                .padding(.vertical, 6)
            }
            .accessibilityLabel("Athlete details, \(profileDisplayName)")
        }
    }

    private var historySection: some View {
        Section("Workout History") {
            NavigationLink {
                WorkoutHistoryView()
            } label: {
                Label("Apple Health History", systemImage: "heart.text.square")
            }

            if historyPlans.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    Text("No workout history yet")
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }
            } else {
                ForEach(Array(historyPlans.prefix(3))) { plan in
                    NavigationLink {
                        WeekReviewView(plan: plan)
                    } label: {
                        WeeklyHistoryRow(plan: plan)
                    }
                    .accessibilityIdentifier("history.week.\(plan.weekNumber)")
                }

                if historyPlans.count > 3 {
                    NavigationLink {
                        WeeklyHistoryListView(plans: historyPlans)
                    } label: {
                        HStack {
                            Label("View all weeks", systemImage: "calendar")
                                .foregroundStyle(.primary)

                            Spacer()

                            Text("\(historyPlans.count)")
                                .font(.subheadline)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        }
                    }
                }
            }
        }
    }

    private var historyPlans: [WeeklyPlan] {
        plans
            .filter { $0.trainingSessions.contains(where: \.isCompleted) }
            .sorted { $0.startDate > $1.startDate }
    }


    private var trainingSection: some View {
        Section("Training") {
            NavigationLink {
                goalEditor
            } label: {
                ProfileNavigationRow(
                    title: "Goal",
                    systemImage: "scope",
                    value: setup.objective.displayName
                )
            }
            .accessibilityIdentifier("profile.goal")

            if let event = setup.objective.event {
                NavigationLink {
                    goalEditor
                } label: {
                    ProfileNavigationRow(
                        title: "Event date",
                        systemImage: "calendar",
                        value: event.eventDate.map {
                            TrainingFormatter.shortDate($0, includeYear: true)
                        } ?? "Not set"
                    )
                }
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

                if setup.objective.event?.sport.requiredTrainingSports.contains(.swimming) == true {
                    NavigationLink {
                        openWaterEditor
                    } label: {
                        ProfileNavigationRow(
                            title: "Open-water training",
                            systemImage: "water.waves",
                            value: setup.openWaterTrainingConsent.permitsPrescription
                                ? "Available"
                                : "Not confirmed"
                        )
                    }
                    .accessibilityIdentifier("profile.openWaterTraining")
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


    private var pendingImpact: ProfileEditImpact {
        guard let opened else { return .safe }
        return AthleteProfileEditor.impact(from: opened, to: setup)
    }

    // MARK: - Focused editors

    private var identityEditor: some View {
        Form {
            Group {
            Section("Athlete") {
                TextField("Name (optional)", text: nameBinding)
                    .textInputAutocapitalization(.words)

                LabeledContent("Level", value: profile.experienceLevel.displayName)

                if !trainedSports.isEmpty {
                    LabeledContent("Sports", value: trainedSports)
                }

                LabeledContent(
                    "Training since",
                    value: TrainingFormatter.shortDate(profile.trainingStartDate, includeYear: true)
                )
            }
            }
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
        .navigationTitle("Athlete")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var goalEditor: some View {
        let draft = objectiveDraft ?? setup.objective

        return Form {
            Group {
            Section {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(TrainingObjectiveKind.allCases, id: \.self) { kind in
                        AtheviaChoiceChip(
                            title: kind.displayName,
                            isSelected: draft.kind == kind
                        ) {
                            var next = draft
                            if kind == .event {
                                if next.kind != .event || next.event == nil {
                                    let sport: EventSport = selectedTrainingSports.count == Sport.allCases.count
                                        ? .triathlon
                                        : EventSport(trainingSport: selectedTrainingSports.first ?? .running) ?? .running
                                    next = .event(
                                        sport: sport,
                                        distance: EventDistance.defaultForSport(sport)
                                    )
                                }
                            } else {
                                next = TrainingObjective(kind: kind)
                            }
                            updateObjectiveDraft(next)
                        }
                        .accessibilityIdentifier("objective.\(kind.rawValue)")
                        .frame(minHeight: 44)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("What are you training for?")
            } footer: {
                Text(draft.kind.detail)
            }

            if draft.kind == .event {
                Section {
                    EventGoalFields(
                        objective: draft,
                        selectedSports: selectedTrainingSports,
                        minimumDate: Calendar.current.startOfDay(for: .now),
                        showsTargetIntent: true,
                        onChange: updateObjectiveDraft
                    )
                    .padding(.vertical, 4)
                }
            }
            }
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
        .navigationTitle("Goal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            objectiveDraft = setup.objective
        }
        .onDisappear {
            objectiveDraft = nil
        }
    }

    private var abilityEditor: some View {
        Form {
            Group {
            if preferences.first(where: { $0.sport == .running })?.isTrained == true {
                Section("Running") {
                    abilityGrid(RunningBaseline.allCases) { baseline in
                        AtheviaChoiceChip(
                            title: runningAbilityLabel(baseline),
                            isSelected: setup.baseline.running == baseline,
                            tint: Discipline.running.tint
                        ) {
                            update { $0.baseline.running = baseline }
                        }
                    }
                }
            }

            if preferences.first(where: { $0.sport == .swimming })?.isTrained == true {
                Section("Swimming") {
                    abilityGrid(SwimmingBaseline.allCases) { baseline in
                        AtheviaChoiceChip(
                            title: baseline.displayName,
                            isSelected: setup.baseline.swimming == baseline,
                            tint: Discipline.swimming.tint
                        ) {
                            update { $0.baseline.swimming = baseline }
                        }
                    }

                    HStack(spacing: 8) {
                        ForEach(SwimStroke.allCases, id: \.self) { stroke in
                            AtheviaChoiceChip(
                                title: stroke.displayName,
                                isSelected: setup.baseline.stroke == stroke,
                                tint: Discipline.swimming.tint
                            ) {
                                update { $0.baseline.stroke = stroke }
                            }
                        }
                    }
                }
            }

            if preferences.first(where: { $0.sport == .cycling })?.isTrained == true {
                Section("Cycling") {
                    abilityGrid(CyclingBaseline.allCases) { baseline in
                        AtheviaChoiceChip(
                            title: cyclingAbilityLabel(baseline),
                            isSelected: setup.baseline.cycling == baseline,
                            tint: Discipline.cycling.tint
                        ) {
                            update { $0.baseline.cycling = baseline }
                        }
                    }
                }
            }
            }
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
        .navigationTitle("Current Ability")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var openWaterEditor: some View {
        Form {
            Group {
            Section {
                Toggle(
                    "Open-water training available",
                    isOn: openWaterBinding(\.explicitlyConfirmed)
                )
                Toggle(
                    "Safe venue available",
                    isOn: openWaterBinding(\.hasSafeVenue)
                )
                Toggle(
                    "I will train with a buddy / supervision",
                    isOn: openWaterBinding(\.hasSupervisionOrBuddy)
                )
            } footer: {
                Text("Athevia only prescribes open-water preparation when all three are confirmed and your current swim capability supports it. Pool training remains available otherwise.")
            }
            }
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
        .navigationTitle("Open Water")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availabilityEditor: some View {
        Form {
            Group {
            Section {
                HStack(spacing: 6) {
                    ForEach(Weekday.trainingWeek, id: \.self) { weekday in
                        profileDayChip(weekday)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Days you can train")
            } footer: {
                if setup.schedule.isUsable {
                    Text("Athevia fits your sessions onto these days and keeps recovery between harder efforts.")
                } else {
                    Text("Choose at least two days so Athevia can build a usable week.")
                }
            }
            }
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
        .navigationTitle("Training Days")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trainingMixEditor: some View {
        Form {
            Group {
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
                Text("Adding a new sport asks for your current starting point before Athevia rebuilds upcoming training. Existing sport progress and completed workouts are preserved.")
            }
            }
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
        .navigationTitle("Training Mix")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if trainingMixNeedsUpdate && newlyAddedSports.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update Plan") {
                        reassess(showConfirmation: true)
                        trainingMixNeedsUpdate = false
                    }
                }
            }
        }
    }

    private var newSportAssessment: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tell Athevia where you are starting in the new sport\(newlyAddedSports.count == 1 ? "" : "s"). Your existing training history will not be reset.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if newlyAddedSports.contains(.running) {
                    Section("Running") {
                        abilityGrid(RunningBaseline.allCases) { baseline in
                            AtheviaChoiceChip(
                                title: runningAbilityLabel(baseline),
                                isSelected: setup.baseline.running == baseline,
                                tint: Discipline.running.tint
                            ) { update { $0.baseline.running = baseline } }
                        }
                    }
                }

                if newlyAddedSports.contains(.cycling) {
                    Section("Cycling") {
                        abilityGrid(CyclingBaseline.allCases) { baseline in
                            AtheviaChoiceChip(
                                title: cyclingAbilityLabel(baseline),
                                isSelected: setup.baseline.cycling == baseline,
                                tint: Discipline.cycling.tint
                            ) { update { $0.baseline.cycling = baseline } }
                        }
                    }
                }

                if newlyAddedSports.contains(.swimming) {
                    Section("Swimming") {
                        abilityGrid(SwimmingBaseline.allCases) { baseline in
                            AtheviaChoiceChip(
                                title: baseline.displayName,
                                isSelected: setup.baseline.swimming == baseline,
                                tint: Discipline.swimming.tint
                            ) { update { $0.baseline.swimming = baseline } }
                        }

                        Picker("Pool length", selection: poolBinding) {
                            Text("25 m").tag(25.0)
                            Text("50 m").tag(50.0)
                            if !isStandardPool {
                                Text("\(Int(profile.poolLengthMeters)) m").tag(profile.poolLengthMeters)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Sport Starting Point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { isPresentingNewSportAssessment = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update Plan") {
                        isPresentingNewSportAssessment = false
                        reassess(showConfirmation: true)
                        newlyAddedSports = []
                        trainingMixNeedsUpdate = false
                    }
                }
            }
        }
    }

    private var swimmingEditor: some View {
        Form {
            Group {
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
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
        .navigationTitle("Swimming")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heartRateEditor: some View {
        Form {
            Group {
            Section {
                Toggle("Use my age for zones", isOn: usesBirthDate)
                    .toggleStyle(AtheviaToggleStyle())

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
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
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
        .background(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface), in: .circle)
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
        selectedTrainingSports
            .map(\.displayName)
            .joined(separator: " · ")
    }

    private var selectedTrainingSports: [Sport] {
        preferences.filter(\.isTrained).map(\.sport)
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

    /// Profile editing always exposes every supported sport. Older/single-sport
    /// profiles may persist only their selected sports, so fill the missing rows
    /// with disabled preferences instead of hiding those sports from the editor.
    private var preferences: [SportPreference] {
        let stored = setup.preferences.isEmpty
            ? SportPreference.defaults(for: setup.baseline)
            : setup.preferences

        return Sport.allCases.map { sport in
            stored.first { $0.sport == sport }
                ?? SportPreference(sport: sport, sessionsPerWeek: 0)
        }
    }

    private var isStandardPool: Bool {
        profile.poolLengthMeters == 25 || profile.poolLengthMeters == 50
    }

    @ViewBuilder
    private func abilityGrid<Value: Hashable, Content: View>(
        _ values: [Value],
        @ViewBuilder content: @escaping (Value) -> Content
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 8
        ) {
            ForEach(values, id: \.self) { value in
                content(value)
            }
        }
        .padding(.vertical, 4)
    }

    private func profileDayChip(_ weekday: Weekday) -> some View {
        let selected = setup.schedule.isAvailable(on: weekday)

        return Button {
            dayBinding(weekday).wrappedValue.toggle()
        } label: {
            Text(weekday.initial)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? theme.color(.onAccent, classic: .white) : theme.color(.text, classic: .primary))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    selected ? theme.color(.accent, classic: .blue) : theme.color(.raisedSurface, classic: Color(uiColor: .tertiarySystemFill)),
                    in: .rect(cornerRadius: 11)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weekday.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func runningAbilityLabel(_ baseline: RunningBaseline) -> String {
        switch baseline {
        case .none: "Not running yet"
        case .runWalk: "Run / walk"
        case .continuous10Minutes: "10 min"
        case .continuous20To30Minutes: "20–30 min"
        case .regular5K: "5 km+"
        }
    }

    private func cyclingAbilityLabel(_ baseline: CyclingBaseline) -> String {
        switch baseline {
        case .under20: "< 20 min"
        case .twentyToThirty: "20–30 min"
        case .thirtyToFortyFive: "30–45 min"
        case .fortyFiveToSixty: "45–60 min"
        case .sixtyPlus: "60+ min"
        }
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
                let wasTrained = preferences.first { $0.sport == sport }?.isTrained == true
                if count == 0,
                   let event = setup.objective.event,
                   event.sport.requiredTrainingSports.contains(sport) {
                    message = "(event.displayName) requires (sport.displayName) training. Change your event first."
                    return
                }

                var current = setup
                var updated = current.preferences.isEmpty
                    ? SportPreference.defaults(for: current.baseline)
                    : current.preferences
                if let index = updated.firstIndex(where: { $0.sport == sport }) {
                    updated[index].sessionsPerWeek = count
                } else {
                    updated.append(SportPreference(sport: sport, sessionsPerWeek: count))
                }
                current.preferences = updated
                profile.setup = current
                save()
                trainingMixNeedsUpdate = true

                if !wasTrained && count > 0 {
                    newlyAddedSports.insert(sport)
                    isPresentingNewSportAssessment = true
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
            return "Without a date of birth, zones become available once you record a hard effort Athevia can measure against."
        }

        return "Estimated maximum \(Int(maximum)) bpm. If you record a harder effort, Athevia uses what you actually did."
    }

    // MARK: - Actions

    private func update(_ change: (inout AthleteSetup) -> Void) {
        let before = setup
        var current = before
        change(&current)
        profile.setup = current
        save()

        let impact = AthleteProfileEditor.impact(from: before, to: current)
        if impact.isTrainingImpacting && !isPresentingNewSportAssessment {
            reassess(showConfirmation: false)
        }
    }

    private func updateObjectiveDraft(_ objective: TrainingObjective) {
        objectiveDraft = objective

        let issues = TrainingObjectiveValidator.issues(
            for: objective,
            selectedSports: selectedTrainingSports,
            asOf: Calendar.current.startOfDay(for: .now)
        )
        guard issues.isEmpty else { return }

        update { $0.objective = objective }
    }

    private func openWaterBinding(
        _ keyPath: WritableKeyPath<OpenWaterTrainingConsent, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { setup.openWaterTrainingConsent[keyPath: keyPath] },
            set: { value in
                update { setup in
                    var consent = setup.openWaterTrainingConsent
                    consent[keyPath: keyPath] = value
                    setup.openWaterTrainingConsent = consent
                }
            }
        )
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            message = "Could not save your changes: \(error.localizedDescription)"
        }
    }


    private func reassess(showConfirmation: Bool = true) {
        guard let plan = plans.currentPlan() else { return }

        do {
            let rebuilt = try PlanStore(context: modelContext).reassess(
                plan,
                poolLengthMeters: profile.poolLengthMeters
            )

            opened = setup
            if showConfirmation {
                message = rebuilt == 0
                    ? "Nothing ahead needed updating this week."
                    : "\(rebuilt) upcoming day\(rebuilt == 1 ? "" : "s") updated."
            }
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

private struct WeeklyHistoryListView: View {
    let plans: [WeeklyPlan]

    var body: some View {
        List(plans) { plan in
            Group {
            NavigationLink {
                WeekReviewView(plan: plan)
            } label: {
                WeeklyHistoryRow(plan: plan)
            }
            .accessibilityIdentifier("history.week.\(plan.weekNumber)")
            }
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WeeklyHistoryRow: View {
    let plan: WeeklyPlan

    private var completed: [PlannedWorkout] {
        plan.trainingSessions.filter(\.isCompleted)
    }

    private var trainingTime: TimeInterval {
        completed.reduce(0) { total, workout in
            total + (workout.importedSummary?.duration ?? workout.estimatedDurationSeconds ?? 0)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(TrainingFormatter.weekRange(start: plan.startDate, end: plan.endDate))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let adherence = plan.adherenceShare {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Plan completed")
                        .font(.caption2)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))

                    Text("\(Int((adherence * 100).rounded()))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let count = completed.count
        let duration = trainingTime > 0
            ? TrainingFormatter.totalDuration(seconds: trainingTime)
            : "No duration"
        return "\(count) workout\(count == 1 ? "" : "s") · \(duration)"
    }
}

private struct ProfileNavigationRow: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }
}

private struct TrainingDaysSummaryRow: View {
    @Environment(\.atheviaTheme) private var theme

    let schedule: AthleteSchedule

    var body: some View {
        HStack(spacing: 12) {
            Text("Training days")
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 6)

            HStack(spacing: 2) {
                ForEach(Weekday.trainingWeek, id: \.self) { weekday in
                    Text(weekday.initial)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(schedule.isAvailable(on: weekday) ? theme.color(.text, classic: Color.onFocusSurface) : Color.secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            schedule.isAvailable(on: weekday)
                                ? AnyShapeStyle(theme.color(.raisedSurface, classic: Color.focusSurface))
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

