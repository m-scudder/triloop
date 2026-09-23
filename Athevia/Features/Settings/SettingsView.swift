import SwiftData
import SwiftUI

struct SettingsView: View {
    var authentication: AuthenticationCoordinator?
    var backup: BackupCoordinator?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthProvider) private var health
    @Query private var profiles: [AthleteProfile]
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    @StateObject private var watch = WatchAvailability.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var healthStatus: HealthAuthorizationStatus = .notDetermined
    @State private var notificationStatus: TrainingNotificationAuthorization = .notDetermined
    @State private var importMessage: String?
    @State private var isWorking = false
    @State private var watchAuthorization: WorkoutSchedulingAuthorization = .notDetermined
    @State private var activeConnection: ConnectionDestination?
    @State private var showsAccountSettings = false
    @State private var showsNotificationSettings = false
    @State private var showsAudioCoachingSettings = false
    @State private var showsDeleteConfirmation = false
    @State private var accountMessage: String?

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
                notificationsSection
                connectionsSection
                automationSection
                developerSection
                accountActions
                versionFooter
            }
            .navigationTitle("Settings")
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                watch.refresh()
                await refreshStatus()
            }
            .refreshable { await refreshStatus() }
            .alert("Apple Health", isPresented: showingImportMessage) {
                Button("OK", role: .cancel) { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
            .sheet(item: $activeConnection) { connection in
                switch connection {
                case .health:
                    HealthConnectionSetupView(
                        status: healthStatus,
                        isWorking: isWorking,
                        connect: connectHealth
                    )
                case .watch:
                    WatchAppSetupView(
                        watch: watch,
                        currentPlan: plans.currentPlan()
                    )
                case .workoutScheduling:
                    WorkoutSchedulingSetupView(
                        isSupported: scheduler.isSupported,
                        authorization: watchAuthorization,
                        isWorking: isWorking,
                        requestAuthorization: connectWatch
                    )
                }
            }
            .sheet(isPresented: $showsNotificationSettings, onDismiss: {
                Task {
                    notificationStatus = await TrainingNotificationManager.shared.authorizationStatus()
                }
            }) {
                NotificationSettingsSheetView()
            }
            .sheet(isPresented: $showsAudioCoachingSettings) {
                AudioCoachingSettingsSheetView()
            }
            .sheet(isPresented: $showsAccountSettings) {
                if let authentication, let backup {
                    AccountBackupSettingsSheetView(
                        authentication: authentication,
                        backup: backup
                    )
                }
            }
            .confirmationDialog(
                "Delete your Athevia account?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account & Cloud Data", role: .destructive) {
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your Athevia account and cloud backups. Training stored locally on this iPhone is not deleted.")
            }
            .alert(
                "Account",
                isPresented: Binding(
                    get: { accountMessage != nil },
                    set: { if !$0 { accountMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { accountMessage = nil }
            } message: {
                Text(accountMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        if let profile = profiles.first {
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

    @ViewBuilder
    private var accountSection: some View {
        if let authentication, backup != nil {
            Button {
                showsAccountSettings = true
            } label: {
                SettingsNavigationRow(
                    title: "Backup",
                    systemImage: "person.crop.circle",
                    value: accountStatusText(authentication)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var trainingSection: some View {
        Button {
            showsAudioCoachingSettings = true
        } label: {
            SettingsNavigationRow(
                title: "Audio coaching",
                systemImage: "speaker.wave.2",
                value: "Runs & rides"
            )
        }
        .buttonStyle(.plain)
    }

    private var notificationsSection: some View {
        Button {
            showsNotificationSettings = true
        } label: {
            SettingsNavigationRow(
                title: "Notifications",
                systemImage: "bell",
                value: notificationStatusText
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var connectionsSection: some View {
        Button {
            activeConnection = .health
        } label: {
            SettingsStatusRow(
                title: "Apple Health",
                systemImage: "heart",
                value: healthStatusText,
                isConnected: healthStatus == .authorized
            )
        }
        .buttonStyle(.plain)
        .disabled(isWorking)

        if watch.isPairedWatch {
            Button {
                activeConnection = .watch
            } label: {
                SettingsStatusRow(
                    title: "Athevia Watch",
                    systemImage: "applewatch",
                    value: watch.isAtheviaWatchInstalled ? "Installed" : "Not installed",
                    isConnected: watch.isAtheviaWatchInstalled
                )
            }
            .buttonStyle(.plain)

            if watch.canSchedule {
                Button {
                    activeConnection = .workoutScheduling
                } label: {
                    SettingsStatusRow(
                        title: "Workout scheduling",
                        systemImage: "calendar.badge.clock",
                        value: watchStatusText,
                        isConnected: watchAuthorization == .authorized
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var automationSection: some View {
        Toggle(isOn: $automaticallyImport) {
            Label("Import workouts automatically", systemImage: "arrow.down.circle")
        }

        if watch.canSchedule {
            Toggle(isOn: $automaticallySchedule) {
                Label("Send workouts to Watch", systemImage: "applewatch")
            }
        }

        Button { importThisWeek() } label: {
            Label("Import completed workouts now", systemImage: "arrow.clockwise")
        }
        .disabled(isWorking || healthStatus != .authorized || plans.isEmpty)
    }

    private var versionFooter: some View {
        Section {
            VStack(spacing: 3) {
                Text("Athevia")
                    .font(.headline.weight(.semibold))
                Text("v\(appVersion)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var developerSection: some View {
        #if DEBUG
        NavigationLink("Simulate training") {
            DeveloperToolsView()
        }
        #endif
    }

    @ViewBuilder
    private var accountActions: some View {
        if let authentication, let backup,
           case .signedIn(let session) = authentication.state {
            Button {
                signOut(session, authentication: authentication, backup: backup)
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(isWorking)

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("Delete Account", systemImage: "trash")
            }
            .disabled(isWorking)
        }
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
        notificationStatus = await TrainingNotificationManager.shared.authorizationStatus()
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
        guard watch.canSchedule else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            watchAuthorization = await scheduler.requestAuthorization()
        }
    }

    private func connectHealth() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await health.requestAuthorization()
                healthStatus = await health.authorizationStatus
            } catch HealthDataError.unavailableOnThisDevice {
                healthStatus = .unavailable
            } catch {
                healthStatus = await health.authorizationStatus
            }
        }
    }

    private func signOut(
        _ session: AccountSession,
        authentication: AuthenticationCoordinator,
        backup: BackupCoordinator
    ) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                _ = try await backup.backup(
                    accountID: session.userID,
                    from: modelContext
                )
                try await authentication.signOut()
                try LocalTrainingStoreState.removeUserData(modelContext)
            } catch {
                accountMessage = "Sign out was not completed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteAccount() {
        guard let authentication else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await authentication.deleteAccount()
            } catch {
                accountMessage = error.localizedDescription
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



private struct AccountBackupSettingsSheetView: View {
    let authentication: AuthenticationCoordinator
    let backup: BackupCoordinator

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AccountBackupSettingsView(
                authentication: authentication,
                backup: backup
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct AudioCoachingSettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AudioCoachingSettingsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct NotificationSettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NotificationSettingsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private enum ConnectionDestination: String, Identifiable {
    case health
    case watch
    case workoutScheduling

    var id: String { rawValue }
}

private struct HealthConnectionSetupView: View {
    let status: HealthAuthorizationStatus
    let isWorking: Bool
    let connect: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ConnectionSheetStatusRow(
                        title: "Apple Health",
                        systemImage: "heart",
                        status: statusText,
                        isConnected: status == .authorized
                    )
                }

                Section {
                    if status == .unavailable {
                        Text("Apple Health is not available on this device.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            connect()
                        } label: {
                            Label(
                                status == .authorized ? "Re-check connection" : "Connect Apple Health",
                                systemImage: status == .authorized ? "arrow.clockwise" : "heart"
                            )
                        }
                        .disabled(isWorking)
                    }
                }
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var statusText: String {
        switch status {
        case .unavailable: "Not available"
        case .notDetermined: "Not connected"
        case .denied: "Denied"
        case .authorized: "Connected"
        }
    }
}

private struct WorkoutSchedulingSetupView: View {
    let isSupported: Bool
    let authorization: WorkoutSchedulingAuthorization
    let isWorking: Bool
    let requestAuthorization: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ConnectionSheetStatusRow(
                        title: "Workout scheduling",
                        systemImage: "calendar.badge.clock",
                        status: statusText,
                        isConnected: authorization == .authorized
                    )
                }

                Section {
                    if !isSupported || authorization == .restricted {
                        Text("Workout scheduling is not available on this device.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            requestAuthorization()
                        } label: {
                            Label(
                                authorization == .authorized ? "Re-check permission" : "Allow workout scheduling",
                                systemImage: authorization == .authorized ? "arrow.clockwise" : "calendar.badge.clock"
                            )
                        }
                        .disabled(isWorking)
                    }
                }
            }
            .navigationTitle("Workout scheduling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var statusText: String {
        guard isSupported else { return "Unavailable" }
        switch authorization {
        case .authorized:
            return "Allowed"
        case .denied:
            return "Not allowed"
        case .restricted:
            return "Not available"
        case .notDetermined:
            return "Not set up"
        }
    }
}

private struct ConnectionSheetStatusRow: View {
    let title: String
    let systemImage: String
    let status: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(.fill.tertiary, in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                HStack(spacing: 5) {
                    if isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Text(status)
                        .foregroundStyle(isConnected ? Color.green : Color.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}


private struct WatchAppSetupView: View {
    @ObservedObject var watch: WatchAvailability
    let currentPlan: WeeklyPlan?

    @Environment(\.dismiss) private var dismiss
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ConnectionSheetStatusRow(
                        title: "Athevia Watch",
                        systemImage: "applewatch",
                        status: watch.isAtheviaWatchInstalled ? "Installed" : "Not installed",
                        isConnected: watch.isAtheviaWatchInstalled
                    )
                }

                if watch.isAtheviaWatchInstalled {
                    Section("Workout Sync") {
                        Label("Your current training week syncs automatically.", systemImage: "checkmark.circle.fill")

                        Button {
                            let queued = WatchAppPlanSync.sync(currentPlan)
                            let count = currentPlan?.trainingSessions.count ?? 0
                            statusMessage = queued
                                ? "Queued \(count) workout\(count == 1 ? "" : "s") for your Apple Watch."
                                : "Athevia could not prepare the current week for Watch sync."
                        } label: {
                            Label("Sync Current Week Now", systemImage: "arrow.triangle.2.circlepath")
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Text("After syncing, workouts remain available in the Athevia Watch app even when your iPhone is not nearby.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Install from your iPhone") {
                        installationStep(
                            number: 1,
                            title: "Open the Watch app",
                            detail: "Use Apple's Watch app on this iPhone."
                        )
                        installationStep(
                            number: 2,
                            title: "Open My Watch",
                            detail: "Scroll to the Available Apps section."
                        )
                        installationStep(
                            number: 3,
                            title: "Find Athevia",
                            detail: "Tap Install next to Athevia."
                        )
                        installationStep(
                            number: 4,
                            title: "Return to Athevia",
                            detail: "Your workouts will sync automatically once installation is detected."
                        )
                    }

                    Section {
                        Button {
                            watch.refresh()
                            statusMessage = watch.isAtheviaWatchInstalled
                                ? "Athevia Watch is installed."
                                : "Athevia Watch is not installed yet."
                        } label: {
                            Label("Check Again", systemImage: "arrow.clockwise")
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("If Automatic App Install is enabled in the Watch app, Athevia may already install automatically.")
                    }
                }
            }
            .navigationTitle("Athevia Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                watch.refresh()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func installationStep(
        number: Int,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.fill.tertiary, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Connected")
            } else {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
