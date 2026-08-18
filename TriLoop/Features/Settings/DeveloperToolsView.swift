#if DEBUG
import SwiftData
import SwiftUI

/// §32 developer tools: exercise the full loop without performing a workout.
///
/// Writes ordinary feedback through the same model methods the UI uses, so what
/// the engine sees here is identical to a real report.
struct DeveloperToolsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeeklyPlan.startDate, order: .reverse) private var plans: [WeeklyPlan]

    @State private var message: String?
    @AppStorage("simulateHealthSamples") private var simulateSamples = false

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
                    Toggle("Simulate chart data", isOn: $simulateSamples)
                } footer: {
                    Text("Generates heart rate, cadence, pace and swim lengths so the charts can be seen without a real HealthKit session.")
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
        _ = PlanStore(context: modelContext).generateNextWeekIfReady(after: plan)
    }

    private func checkIn(_ plan: WeeklyPlan, pain: Int, soreness: SorenessLevel, energy: EnergyLevel) {
        for workout in plan.trainingSessions where workout.hasReport {
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
