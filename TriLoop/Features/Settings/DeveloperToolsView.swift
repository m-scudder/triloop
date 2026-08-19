#if DEBUG
import SwiftData
import SwiftUI

/// §32 developer tools: exercise the full loop without performing a workout.
///
/// Writes ordinary feedback through the same model methods the UI uses, so what
/// the engine sees here is identical to a real report.
struct DeveloperToolsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthProvider) private var health
    @Query(sort: \WeeklyPlan.startDate, order: .reverse) private var plans: [WeeklyPlan]

    @State private var message: String?
    @State private var source = HealthProviderResolver.selected
    @State private var dataset = SimulationSettings.dataset

    /// Chooses what the app reads health data from.
    ///
    /// The provider is resolved once at launch, so a change here needs a
    /// relaunch to take effect — saying so is better than appearing to switch
    /// and leaving half the app on the old data.
    @ViewBuilder
    private var healthSourceSection: some View {
        Section {
            Picker("Source", selection: $source) {
                ForEach(HealthDataSource.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .onChange(of: source) { _, newValue in
                HealthProviderResolver.selected = newValue
                message = "Source set to \(newValue.displayName). Relaunch to apply."
            }

            if source == .simulated {
                Picker("Dataset", selection: $dataset) {
                    ForEach(SimulationDataset.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .onChange(of: dataset) { _, newValue in
                    SimulationSettings.dataset = newValue
                    message = "Dataset set to \(newValue.displayName). Relaunch to apply."
                }

                Text(dataset.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Health data source")
        } footer: {
            Text("Simulated data is Debug-only, never written back to Health, and never used by a release build. Relaunch after changing.")
        }

        Section {
            NavigationLink("Browse workout history") {
                WorkoutHistoryView()
            }
        } footer: {
            Text("Everything in Health, including activities TriLoop does not train. Read-only, with load, intensity and sport balance computed from the workouts you filter to.")
        }
    }

    private struct Scenario: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let draft: FeedbackDraft
    }

    private let scenarios: [Scenario] = [
        Scenario(
            name: "Easy week",
            detail: "RPE 3, no pain, good recovery — expect every sport to progress",
            draft: FeedbackDraft(rpe: 3, painScore: 0, recoveryFeeling: .good)
        ),
        Scenario(
            name: "Hard week",
            detail: "RPE 7, pain 1 — expect maintain",
            draft: FeedbackDraft(rpe: 7, painScore: 1, recoveryFeeling: .okay)
        ),
        Scenario(
            name: "Painful week",
            detail: "RPE 8, pain 5 — expect reduce",
            draft: FeedbackDraft(rpe: 8, painScore: 5, painLocations: [.shin], recoveryFeeling: .tired)
        ),
        Scenario(
            name: "Warning symptom",
            detail: "Dizziness reported — expect recovery required",
            draft: FeedbackDraft(rpe: 3, painScore: 0, symptoms: [.dizziness])
        )
    ]

    var body: some View {
        List {
            healthSourceSection

            if let plan = simulationPlan {
                Section {
                    ForEach(scenarios) { scenario in
                        Button {
                            complete(plan, with: scenario.draft)
                            message = "\(scenario.name) applied to week \(plan.weekNumber)."
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scenario.name)
                                Text(scenario.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Report week \(plan.weekNumber)")
                } footer: {
                    Text("Fills every training session with the same report, then creates the next week automatically.")
                }

                Section("Recovery check-ins") {
                    Button("Add good check-ins") {
                        checkIn(plan, pain: 0, soreness: .none, energy: .good)
                        message = "Good check-ins added."
                    }
                    Button("Add sore check-ins") {
                        checkIn(plan, pain: 0, soreness: .moderate, energy: .low)
                        message = "Sore check-ins added — progression should be held."
                    }
                }

                Section {
                    if source == .simulated {
                        Button("Attach simulated Health workouts") {
                            Task { await attachFromProvider(plan) }
                        }
                    } else {
                        Text("Switch Source to Simulated Data above to attach fixture workouts.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    // Fabricated summaries carry a random UUID that HealthKit
                    // cannot resolve, so no samples come back and the charts
                    // stay empty. Provider workouts keep their fixture id.
                    Text("Takes workouts from the chosen dataset, so heart-rate charts, zones, intensity and load all render through the production path.")
                }

                Section {
                    Button("Strip evidence from week \(plan.weekNumber)") {
                        stripEvidence(plan)
                        message = "Reports and recorded data removed."
                    }
                } footer: {
                    Text("Leaves the sessions in place with no report and no Health data, so the unmeasured case can be checked.")
                }

                Section {
                    Button("Attach recorded data — as prescribed") {
                        attachRecorded(plan, factor: 0.97)
                        message = "Recorded data attached at full completion."
                    }
                    Button("Attach recorded data — half completed") {
                        attachRecorded(plan, factor: 0.5)
                        message = "Recorded data attached at 50%. Expect reduce."
                    }
                } header: {
                    Text("Simulated Apple Health")
                } footer: {
                    Text("Stands in for an import so Workout Detail shows a Recorded section. Uses TriLoop's own model, not HealthKit.")
                }

                Section {
                    Button("Clear all reports", role: .destructive) {
                        for workout in plan.trainingSessions {
                            workout.clearCompletion()
                        }
                        try? modelContext.save()
                        message = "Reports cleared."
                    }
                }
            } else {
                Text("No plan available.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Start over — erase everything", role: .destructive) {
                    SeedDataInstaller.eraseAll(in: modelContext)
                    message = "Everything erased. Relaunch to go through setup."
                }

                Button("Reset seed data", role: .destructive) {
                    SeedDataInstaller.reset(in: modelContext)
                    message = "Seed reinstalled."
                }
            } footer: {
                Text("Erasing clears the athlete profile too, so the app returns to first-run setup. Resetting reinstalls the fixed week one without touching setup.")
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Developer", isPresented: showingMessage) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var showingMessage: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    /// Calendar selection stays on the real current week; simulation instead
    /// advances through the first plan that has not already been completed.
    private var simulationPlan: WeeklyPlan? {
        plans
            .filter { $0.status != .completed }
            .min { $0.weekNumber < $1.weekNumber }
    }

    private func complete(_ plan: WeeklyPlan, with draft: FeedbackDraft) {
        for workout in plan.trainingSessions {
            workout.recordCompletion(with: draft)
        }
        try? modelContext.save()
        _ = try? PlanStore(context: modelContext).generateNextWeekIfReady(after: plan)
    }

    /// Attaches workouts from whichever provider is selected.
    ///
    /// Matched by sport rather than by date: a fixture's days rarely coincide
    /// with the plan's, and the point is to populate the week rather than to
    /// exercise the matcher.
    private func attachFromProvider(_ plan: WeeklyPlan) async {
        let end = Date.now
        guard let start = Calendar.current.date(byAdding: .day, value: -120, to: end),
              let workouts = try? await health.workouts(from: start, to: end) else {
            message = "Could not read workouts from the selected source."
            return
        }

        let known = Set(
            (try? modelContext.fetch(FetchDescriptor<ImportedWorkoutSummary>()))?.map(\.healthKitUUID) ?? []
        )
        var available = workouts.filter { !known.contains($0.healthKitUUID) }

        var attached = 0
        for session in plan.trainingSessions where session.importedSummary == nil {
            guard let sport = session.discipline.sport,
                  let index = available.firstIndex(where: { $0.sport == sport }) else { continue }

            let summary = ImportedWorkoutSummary(available.remove(at: index))
            modelContext.insert(summary)
            session.attach(summary)
            attached += 1
        }

        guard attached > 0 else {
            message = "No unused workouts matched this week's sports."
            return
        }

        try? modelContext.save()
        message = "Attached \(attached) workout\(attached == 1 ? "" : "s") with full sample data."
    }

    /// Removes every trace of what happened, leaving sessions that took place
    /// with nothing measuring them — the one case real data rarely produces.
    private func stripEvidence(_ plan: WeeklyPlan) {
        for workout in plan.trainingSessions {
            if let feedback = workout.feedback {
                modelContext.delete(feedback)
                workout.feedback = nil
            }
            if let summary = workout.importedSummary {
                modelContext.delete(summary)
                workout.importedSummary = nil
            }
        }
        try? modelContext.save()
    }

    private func checkIn(_ plan: WeeklyPlan, pain: Int, soreness: SorenessLevel, energy: EnergyLevel) {        for workout in plan.trainingSessions where workout.hasReport {
            workout.recordRecoveryCheckIn(painScore: pain, soreness: soreness, energy: energy)
        }
        try? modelContext.save()
    }

    /// Plausible per-sport metrics. Every sport records heart rate, including
    /// pool swims; only ascent is genuinely absent indoors.
    private func attachRecorded(_ plan: WeeklyPlan, factor: Double) {
        for workout in plan.trainingSessions {
            guard let sport = workout.discipline.sport else { continue }

            let start = Calendar.current.date(bySettingHour: 7, minute: 12, second: 0, of: workout.date) ?? workout.date
            let duration = (workout.estimatedDurationSeconds ?? 1800) * factor
            let distanceOverride = workout.estimatedDistanceMeters.map { $0 * factor }
            let heartRate = averageHeartRate(for: sport)
            let distance = (distanceOverride ?? estimatedDistance(for: sport, seconds: duration))
            let lengths = sport == .swimming ? Int((distance ?? 0) / 25) : nil

            let summary = ImportedWorkoutSummary(
                healthKitUUID: UUID(),
                sport: sport,
                startDate: start,
                endDate: start.addingTimeInterval(duration),
                duration: duration,
                distanceMeters: distance,
                averageHeartRate: heartRate,
                maximumHeartRate: heartRate + 26,
                elevationAscendedMeters: sport == .cycling ? 85 : nil,
                swimmingLengths: lengths,
                swimmingStrokeCount: lengths.map { Double($0) * 19 },
                // Two lengths without stopping, which is the beginner reality.
                longestContinuousSwimMeters: lengths.map { _ in 50 },
                metrics: RecordedMetrics(averageCadence: sport == .running ? 162 : nil),
                source: "com.apple.workout"
            )

            modelContext.insert(summary)
            workout.attach(summary)
        }
        try? modelContext.save()
    }

    private func averageHeartRate(for sport: Sport) -> Double {
        switch sport {
        case .running: 142
        case .swimming: 131
        case .cycling: 128
        }
    }

    private func estimatedDistance(for sport: Sport, seconds: TimeInterval) -> Double? {
        switch sport {
        case .running: seconds * 2.2      // ~7:35 / km
        case .cycling: seconds * 5.0      // ~18 km/h
        case .swimming: nil
        }
    }
}
#endif
