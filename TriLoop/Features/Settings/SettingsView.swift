import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [AthleteProfile]
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    @State private var healthStatus: HealthAuthorizationStatus = .notDetermined
    @State private var importMessage: String?
    @State private var isWorking = false
    @State private var scheduledWorkouts: [ScheduledWorkoutSummary] = []
    @State private var watchAuthorization: WorkoutSchedulingAuthorization = .notDetermined
    @State private var permissionMessage: String?
    @AppStorage("automaticallyScheduleWorkouts") private var automaticallySchedule = false
    @AppStorage("automaticallyImportWorkouts") private var automaticallyImport = true

    private let health = HealthKitWorkoutImporter()
    private let scheduler = WorkoutKitScheduler()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Each row is the status and the action. Requesting again
                    // when already granted is harmless, so there is always a
                    // route back from a permission removed by mistake.
                    Button { connectHealth() } label: {
                        LabeledContent("Apple Health", value: healthStatusText)
                    }
                    .disabled(isWorking || healthStatus == .unavailable)

                    Button { connectWatch() } label: {
                        LabeledContent("Apple Watch", value: watchStatusText)
                    }
                    .disabled(isWorking || !scheduler.isSupported || watchAuthorization == .restricted)
                } header: {
                    Text("Connections")
                } footer: {
                    Text("Tap a row to grant or re-check.")
                }

                Section {
                    Button("Import completed workouts") { importThisWeek() }
                        .disabled(isWorking || healthStatus != .authorized || plans.isEmpty)

                    Toggle("Import automatically", isOn: $automaticallyImport)

                    Toggle("Send week to Apple Watch automatically", isOn: $automaticallySchedule)
                } header: {
                    Text("Workouts")
                } footer: {
                    Text("Automatic import links a session as soon as Apple Health records it, and checks again each time you open TriLoop.")
                }

                if let profile = profiles.first {
                    Section {
                        NavigationLink {
                            TrainingProfileView(profile: profile)
                        } label: {
                            LabeledContent("Training profile", value: profile.setup?.goal.displayName ?? "Not set")
                        }
                    } header: {
                        Text("Training")
                    } footer: {
                        Text("Your goal, what you can do today, the days you train and the pool you use.")
                    }
                }

                Section {
                    LabeledContent("Storage", value: "On this device")
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
                } footer: {
                    Text("TriLoop keeps your training data on your device. There is no account and no cloud sync.")
                }

                #if DEBUG
                Section("Developer") {
                    NavigationLink("Apple Watch schedule") {
                        ScheduledWorkoutsView(
                            isSupported: scheduler.isSupported,
                            authorization: watchAuthorization,
                            entries: scheduledWorkouts,
                            refresh: refreshSchedule
                        )
                    }
                    NavigationLink("Simulate training") {
                        DeveloperToolsView()
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .task { await refreshStatus() }
            .refreshable { await refreshStatus() }
            .alert("Apple Health", isPresented: showingImportMessage) {
                Button("OK", role: .cancel) { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
            .alert(
                "Permissions",
                isPresented: Binding(
                    get: { permissionMessage != nil },
                    set: { if !$0 { permissionMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { permissionMessage = nil }
            } message: {
                Text(permissionMessage ?? "")
            }
        }
    }

    private func refreshStatus() async {
        isWorking = true
        defer { isWorking = false }
        healthStatus = await health.authorizationStatus
        watchAuthorization = await scheduler.authorizationState()
        scheduledWorkouts = await scheduler.scheduledWorkouts()
    }

    private func refreshSchedule() async {
        watchAuthorization = await scheduler.authorizationState()
        scheduledWorkouts = await scheduler.scheduledWorkouts()
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var showingImportMessage: Binding<Bool> {
        Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )
    }

    private var healthStatusText: String {
        switch healthStatus {
        case .unavailable: "Not available"
        case .notDetermined: "Not connected"
        case .denied: "Denied"
        case .authorized: "Connected"
        }
    }

    private var watchStatusText: String {
        guard scheduler.isSupported else { return "Unavailable" }
        switch watchAuthorization {
        case .authorized: return "Allowed"
        case .denied: return "Not allowed"
        case .restricted: return "Not available"
        case .notDetermined: return "Not set up"
        }
    }

    private func connectWatch() {
        isWorking = true
        Task {
            defer { isWorking = false }
            let before = watchAuthorization
            watchAuthorization = await scheduler.requestAuthorization()

            permissionMessage = switch watchAuthorization {
            case .authorized:
                "Workout scheduling is allowed."
            case .restricted:
                "The system will not allow scheduling on this device."
            case .denied where before == .denied:
                "iOS did not show a prompt because the answer is already recorded. Reinstalling TriLoop clears it."
            case .denied:
                "Workout scheduling was declined."
            case .notDetermined:
                "No response from the system. Check that your Watch is unlocked and nearby."
            }
        }
    }

    private func connectHealth() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await health.requestAuthorization()
                healthStatus = await health.authorizationStatus

                permissionMessage = healthStatus == .authorized
                    ? "Apple Health has been asked already. To change what TriLoop can read, open the Health app, tap your profile picture, then Apps, then TriLoop."
                    : "Apple Health did not grant access. Open the Health app, tap your profile picture, then Apps, then TriLoop."
            } catch HealthDataError.unavailableOnThisDevice {
                permissionMessage = "Apple Health is not available on this device."
            } catch {
                permissionMessage = "Could not connect to Apple Health."
            }
        }
    }

    private func importThisWeek() {
        guard let plan = plans.currentPlan() else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let service = WorkoutImportService(context: modelContext, provider: health)
                let outcome = try await service.importWorkouts(for: plan)
                importMessage = message(for: outcome)
            } catch {
                importMessage = "Import failed."
            }
        }
    }

    private func message(for outcome: WorkoutImportService.Outcome) -> String {
        if outcome.matched > 0 {
            let sessions = outcome.matched == 1 ? "session" : "sessions"
            return "Matched \(outcome.matched) \(sessions). Add how each one felt to complete them."
        }
        if outcome.alreadyKnown > 0 {
            return "Nothing new since the last import."
        }
        return "No matching workouts found for this week."
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
