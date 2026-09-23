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
    @State private var showsEraseLocalConfirmation = false
    @State private var accountMessage: String?

    @AppStorage("automaticallyScheduleWorkouts") private var automaticallySchedule = true
    @AppStorage("automaticallyImportWorkouts") private var automaticallyImport = true
    @AppStorage(TrainingNotificationPreferences.enabledKey) private var notificationsEnabled = false

    private let scheduler = WorkoutKitScheduler()

    var body: some View {
        NavigationStack {
            List {
                profileSection
                trainingSection
                notificationsSection
                connectionsSection
                automationSection
                developerSection
                accountSection
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
                        currentPlan: plans.currentPlan(),
                        schedulingAuthorization: watchAuthorization,
                        isWorking: isWorking,
                        requestSchedulingAuthorization: connectWatch
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
                "Erase Athevia data from this iPhone?",
                isPresented: $showsEraseLocalConfirmation,
                titleVisibility: .visible
            ) {
                Button("Erase Local Athevia Data", role: .destructive) {
                    eraseLocalData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes Athevia training data from this iPhone and clears Athevia workouts from the paired Watch. Apple Health workouts are not deleted.")
            }
            .confirmationDialog(
                "Delete your Athevia account?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account & All Athevia Data", role: .destructive) {
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your Athevia account, cloud backups, and Athevia training data stored on this iPhone. Apple Health workouts are not deleted.")
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
                SettingsStatusRow(
                    title: "Cloud Backup",
                    systemImage: "person.crop.circle",
                    value: accountStatusText(authentication),
                    isConnected: {
                        if case .signedIn = authentication.state {
                            return true
                        }
                        return false
                    }()
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
                value: nil
            )
        }
        .buttonStyle(.plain)
    }

    private var notificationsSection: some View {
        Button {
            showsNotificationSettings = true
        } label: {
            SettingsStatusRow(
                title: "Notifications",
                systemImage: "bell",
                value: notificationStatusText,
                isConnected: notificationStatus == .authorized && notificationsEnabled
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
                    title: "Apple Watch",
                    systemImage: "applewatch",
                    value: watch.isAtheviaWatchInstalled ? "Connected" : "App not installed",
                    isConnected: watch.isAtheviaWatchInstalled
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var automationSection: some View {
        Toggle(isOn: $automaticallyImport) {
            Label("Auto Import Workout", systemImage: "arrow.down.circle")
        }
        .tint(.green)

        if watch.isPairedWatch && watch.canSchedule {
            Toggle(isOn: $automaticallySchedule) {
                Label("Send workouts to Watch", systemImage: "applewatch")
            }
            .tint(.green)
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
        if let authentication, let backup {
            switch authentication.state {
            case .signedIn(let session):
                Button {
                    signOut(session, authentication: authentication, backup: backup)
                } label: {
                    Label {
                        Text("Sign Out")
                    } icon: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline)
                            .frame(width: 20)
                    }
                }
                .disabled(isWorking)

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete Account", systemImage: "trash")
                }
                .disabled(isWorking)

            case .signedOut, .failed:
                Button(role: .destructive) {
                    showsEraseLocalConfirmation = true
                } label: {
                    Label("Erase Athevia Data", systemImage: "trash")
                }
                .disabled(isWorking)

            case .checking, .signingIn:
                EmptyView()
            }
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
            "On this iPhone"
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

    private func eraseLocalData() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            await clearSignedOutAccountData()
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
                try await AccountExitFlow.signOut(
                    finalBackup: {
                        _ = try await backup.backup(
                            accountID: session.userID,
                            from: modelContext
                        )
                    },
                    remoteSignOut: {
                        try await authentication.signOut()
                    },
                    cleanup: {
                        await clearSignedOutAccountData()
                    }
                )
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
                accountMessage = "Account deletion was not completed: \(error.localizedDescription)"
                return
            }

            await clearSignedOutAccountData()
        }
    }

    private func clearSignedOutAccountData() async {
        var localCleanupError: Error?

        do {
            try LocalTrainingStoreState.removeUserData(modelContext)
        } catch {
            localCleanupError = error
        }

        // Account-specific reminders and Watch payloads must not survive into
        // the next signed-in account on the same iPhone/Watch pair.
        await TrainingNotificationManager.shared.removeAllOwnedPendingRequests()
        _ = WatchAppPlanSync.sync(nil)

        if scheduler.isSupported {
            await scheduler.removeAllScheduled()
        }

        if let localCleanupError {
            accountMessage = "Athevia could not erase all local training data: \(localCleanupError.localizedDescription). Please reinstall the app before using another account."
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
    let schedulingAuthorization: WorkoutSchedulingAuthorization
    let isWorking: Bool
    let requestSchedulingAuthorization: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    ConnectionSheetStatusRow(
                        title: "Apple Watch",
                        systemImage: "applewatch",
                        status: watch.isPairedWatch ? "Paired" : "Not paired",
                        isConnected: watch.isPairedWatch
                    )

                    ConnectionSheetStatusRow(
                        title: "Athevia Watch app",
                        systemImage: "app.badge.checkmark",
                        status: watch.isAtheviaWatchInstalled ? "Installed" : "Not installed",
                        isConnected: watch.isAtheviaWatchInstalled
                    )

                    if watch.canSchedule {
                        ConnectionSheetStatusRow(
                            title: "Workout scheduling",
                            systemImage: "calendar.badge.clock",
                            status: schedulingStatusText,
                            isConnected: schedulingAuthorization == .authorized
                        )
                    }
                }

                if watch.canSchedule {
                    Section("Apple Workout Scheduling") {
                        Button {
                            requestSchedulingAuthorization()
                        } label: {
                            Label(
                                schedulingAuthorization == .authorized
                                    ? "Re-check scheduling permission"
                                    : "Allow workout scheduling",
                                systemImage: schedulingAuthorization == .authorized
                                    ? "arrow.clockwise"
                                    : "calendar.badge.clock"
                            )
                        }
                        .disabled(isWorking)
                    } footer: {
                        Text("This lets Athevia place structured sessions in Apple's Workout app. It is separate from the Athevia Watch app.")
                    }
                }

                if watch.isAtheviaWatchInstalled {
                    Section("Athevia Workout Sync") {
                        Label(
                            "Your current training week syncs automatically.",
                            systemImage: "checkmark.circle.fill"
                        )

                        if let lastQueuedAt = WatchAppPlanSync.lastQueuedAt {
                            LabeledContent(
                                "Last sent",
                                value: TrainingFormatter.shortDateTime(lastQueuedAt, includeYear: false)
                            )
                            .font(.subheadline)
                        }

                        Button {
                            let queued = WatchAppPlanSync.sync(currentPlan)
                            let count = currentPlan?.trainingSessions.count ?? 0
                            statusMessage = queued
                                ? "Sent \(count) workout\(count == 1 ? "" : "s") to the Watch sync queue."
                                : "Athevia could not prepare the current week for Watch sync."
                        } label: {
                            Label("Sync Current Week Now", systemImage: "arrow.triangle.2.circlepath")
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("“Last sent” means the latest plan was queued by this iPhone. Delivery completes when the Watch connection is available.")
                    }
                } else {
                    Section("Install Athevia Watch") {
                        installationStep(
                            number: 1,
                            title: "Open the Watch app",
                            detail: "Use Apple's Watch app on this iPhone."
                        )
                        installationStep(
                            number: 2,
                            title: "Open My Watch",
                            detail: "Scroll to Available Apps."
                        )
                        installationStep(
                            number: 3,
                            title: "Find Athevia",
                            detail: "Tap Install next to Athevia."
                        )
                        installationStep(
                            number: 4,
                            title: "Return to Athevia",
                            detail: "Your current week will sync automatically."
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
                    }
                }
            }
            .navigationTitle("Apple Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { watch.refresh() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var schedulingStatusText: String {
        switch schedulingAuthorization {
        case .authorized: "Allowed"
        case .denied: "Not allowed"
        case .restricted: "Not available"
        case .notDetermined: "Not set up"
        }
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
    let value: String?

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
