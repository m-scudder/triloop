import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    var authentication: AuthenticationCoordinator?
    var backup: BackupCoordinator?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthProvider) private var health
    @Query private var profiles: [AthleteProfile]
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    @State private var healthStatus: HealthAuthorizationStatus = .notDetermined
    @State private var notificationStatus: TrainingNotificationAuthorization = .notDetermined
    @State private var importMessage: String?
    @State private var isWorking = false
    @State private var scheduledWorkouts: [ScheduledWorkoutSummary] = []
    @State private var watchAuthorization: WorkoutSchedulingAuthorization = .notDetermined
    @State private var permissionMessage: String?

    @AppStorage("automaticallyScheduleWorkouts") private var automaticallySchedule = true
    @AppStorage("automaticallyImportWorkouts") private var automaticallyImport = true
    @AppStorage(TrainingNotificationPreferences.enabledKey) private var notificationsEnabled = false

    private let scheduler = WorkoutKitScheduler()

    var body: some View {
        NavigationStack {
            List {
                profileSection
                accountSection
                trainingSection
                connectionsSection
                automationSection
                aboutSection
                developerSection
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

    @ViewBuilder
    private var profileSection: some View {
        if let profile = profiles.first {
            Section {
                NavigationLink {
                    TrainingProfileView(profile: profile)
                } label: {
                    HStack(spacing: 14) {
                        profileAvatar(profile)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(profileDisplayName(profile))
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(profileSummary(profile))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .accessibilityLabel("Training profile, \(profileDisplayName(profile))")
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if let authentication, let backup {
            Section("Account") {
                NavigationLink {
                    AccountBackupSettingsView(
                        authentication: authentication,
                        backup: backup
                    )
                } label: {
                    SettingsNavigationRow(
                        title: "Account & Backup",
                        systemImage: "person.crop.circle",
                        value: accountStatusText(authentication)
                    )
                }
            }
        }
    }

    private var trainingSection: some View {
        Section("Training") {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                SettingsNavigationRow(
                    title: "Notifications",
                    systemImage: "bell",
                    value: notificationStatusText
                )
            }
        }
    }

    private var connectionsSection: some View {
        Section {
            Button { connectHealth() } label: {
                SettingsStatusRow(
                    title: "Apple Health",
                    systemImage: "heart",
                    value: healthStatusText
                )
            }
            .buttonStyle(.plain)
            .disabled(isWorking || healthStatus == .unavailable)

            Button { connectWatch() } label: {
                SettingsStatusRow(
                    title: "Apple Watch",
                    systemImage: "applewatch",
                    value: watchStatusText
                )
            }
            .buttonStyle(.plain)
            .disabled(isWorking || !scheduler.isSupported || watchAuthorization == .restricted)
        } header: {
            Text("Connections")
        } footer: {
            Text("Tap a connection to grant or re-check its permission.")
        }
    }

    private var automationSection: some View {
        Section {
            Toggle(isOn: $automaticallyImport) {
                Label("Import workouts automatically", systemImage: "arrow.down.circle")
            }

            Toggle(isOn: $automaticallySchedule) {
                Label("Send workouts to Watch", systemImage: "applewatch")
            }

            Button { importThisWeek() } label: {
                Label("Import completed workouts now", systemImage: "arrow.clockwise")
            }
            .disabled(isWorking || healthStatus != .authorized || plans.isEmpty)
        } header: {
            Text("Automation")
        } footer: {
            Text("TriLoop can match completed workouts from Apple Health and keep the remaining week available on Apple Watch.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Storage", value: storageStatusText)
            LabeledContent("Version", value: appVersion)
        }
    }

    @ViewBuilder
    private var developerSection: some View {
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

    private func profileAvatar(_ profile: AthleteProfile) -> some View {
        Group {
            if let monogram = monogram(of: profile.name) {
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

    private func profileDisplayName(_ profile: AthleteProfile) -> String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Training Profile" : trimmed
    }

    private func profileSummary(_ profile: AthleteProfile) -> String {
        let setup = profile.setup ?? AthleteSetup()
        let sports = profileSports(setup)
        let goal = setup.goal.displayName
        return sports.isEmpty ? goal : "\(sports) · \(goal)"
    }

    private func profileSports(_ setup: AthleteSetup) -> String {
        let preferences = setup.preferences.isEmpty
            ? SportPreference.defaults(for: setup.baseline)
            : setup.preferences

        return preferences
            .filter(\.isTrained)
            .map { $0.sport.displayName }
            .joined(separator: " · ")
    }

    private func monogram(of name: String) -> String? {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }

    private func refreshStatus() async {
        isWorking = true
        defer { isWorking = false }
        healthStatus = await health.authorizationStatus
        watchAuthorization = await scheduler.authorizationState()
        scheduledWorkouts = await scheduler.scheduledWorkouts()
        notificationStatus = await TrainingNotificationManager.shared.authorizationStatus()
    }

    private func refreshSchedule() async {
        watchAuthorization = await scheduler.authorizationState()
        scheduledWorkouts = await scheduler.scheduledWorkouts()
    }

    private func accountStatusText(_ authentication: AuthenticationCoordinator) -> String {
        switch authentication.state {
        case .signedIn:
            "Signed in"
        case .checking, .signingIn:
            "Checking…"
        case .signedOut:
            "Not signed in"
        case .failed:
            "Needs attention"
        }
    }

    private var storageStatusText: String {
        guard let authentication else { return "On this device" }
        if case .signedIn = authentication.state {
            return "Device + backup"
        }
        return "On this device"
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

    private var notificationStatusText: String {
        switch notificationStatus {
        case .notDetermined: "Not set up"
        case .denied: "Off in iOS"
        case .authorized: notificationsEnabled ? "On" : "Paused"
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

private struct SettingsNavigationRow: View {
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
        }
    }
}

private struct SettingsStatusRow: View {
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
        }
        .contentShape(.rect)
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
#endif
