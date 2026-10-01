import SwiftData
import SwiftUI

private enum RootTab: Hashable {
    case home
    case plan
    case progress
    case settings
}

struct RootView: View {
    var storeOutcome: StoreOutcome = .opened
    var autoImporter: WorkoutAutoImporter?
    var authentication: AuthenticationCoordinator?
    var backup: BackupCoordinator?
    var automaticBackup: AutomaticBackupController?

    @Query private var profiles: [AthleteProfile]
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @Query(sort: \StoredWorkoutTemplate.updatedAt) private var templates: [StoredWorkoutTemplate]
    @State private var hasShownStoreAlert = false
    @State private var selectedTab: RootTab = .home
    @State private var lastKnownHighestWeek: Int?
    @State private var accountReady = false
    @State private var isErasingLocalData = false
    @AppStorage("automaticallyImportWorkouts") private var automaticallyImport = true
    @AppStorage(AtheviaTheme.preferenceKey) private var gamingThemeEnabled = false
    @AppStorage(GamingPalette.preferenceKey) private var gamingPalette = GamingPalette.neon.rawValue
    @AppStorage("automaticallyScheduleWorkouts") private var automaticallySchedule = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    /// Setup state is asked of the profile rather than inferred from whether a
    /// plan exists: an athlete migrated from an earlier build has plans but has
    /// never been asked anything.
    private var needsSetup: Bool {
        profiles.first?.hasCompletedSetup != true
    }

    private var bypassesAccountAccessForUITests: Bool {
        #if DEBUG
        ContentDensityUITestFixture.isEnabled
        #else
        false
        #endif
    }

    var body: some View {
        lifecycleContent
            .alert("Training data was reset", isPresented: showStoreAlert) {
                Button("OK", role: .cancel) { hasShownStoreAlert = true }
            } message: {
                Text(storeMessage)
            }
    }

    // Opaque view boundaries keep each modifier chain small enough for the
    // SwiftUI type checker, without type erasure or changes to view identity.
    private var rootContent: some View {
        Group {
            if isErasingLocalData {
                ProgressView("Resetting Athevia…")
            } else if let authentication, let backup, !accountReady, !bypassesAccountAccessForUITests {
                AccountAccessView(
                    authentication: authentication,
                    backup: backup,
                    onReady: { session, seedLocalBackup in
                        ProductAnalytics.shared.updateAccount(session.userID)
                        accountReady = true
                        if seedLocalBackup {
                            seedAutomaticBackup(for: session)
                        }
                    },
                    onContinueLocally: {
                        ProductAnalytics.shared.updateAccount(signedInAccountID)
                        accountReady = true
                    }
                )
            } else {
                localApp
            }
        }
    }

    private var themedContent: some View {
        rootContent
            .symbolRenderingMode(.monochrome)
            .atheviaTheme(rootTheme)
            .onChange(of: gamingPalette) { _, _ in
                Task { await WorkoutLiveActivityController.refreshTheme() }
            }
            .onChange(of: gamingThemeEnabled) { _, _ in
                // Refresh the existing session without recreating navigation.
                Task { await WorkoutLiveActivityController.refreshTheme() }
            }
    }

    private var lifecycleContent: some View {
        themedContent
            .onChange(of: scenePhase, initial: true) { _, phase in
                ProductAnalytics.shared.setActive(phase == .active)
            }
            .onChange(of: backupFingerprint) { _, _ in
                scheduleAutomaticBackupIfNeeded()
            }
            .onChange(of: authentication?.state, initial: true) { previous, current in
                synchronizeAnalyticsAccount(current)
                handleAccountChange(from: accountID(in: previous), to: accountID(in: current))
            }
            .task(id: scenePhase) {
                await flushBackupWhenInactive()
            }
    }

    private var rootTheme: AtheviaTheme {
        AtheviaTheme(
            gamingEnabled: gamingThemeEnabled,
            palette: GamingPalette.resolve(gamingPalette)
        )
    }

    private func accountID(in state: AuthenticationCoordinatorState?) -> String? {
        guard let state, case .signedIn(let session) = state else { return nil }
        return session.userID
    }

    private func synchronizeAnalyticsAccount(_ state: AuthenticationCoordinatorState?) {
        guard let state else {
            ProductAnalytics.shared.updateAccount(nil)
            return
        }
        switch state {
        case .signedIn(let session):
            ProductAnalytics.shared.updateAccount(session.userID)
        case .signedOut:
            ProductAnalytics.shared.updateAccount(nil)
        case .failed:
            ProductAnalytics.shared.accountResolutionFailed()
        case .checking, .signingIn:
            // A refresh or failed request is not proof of logout.
            ProductAnalytics.shared.waitForAccountResolution()
        }
    }

    private func handleAccountChange(from previousAccountID: String?, to newAccountID: String?) {
        guard newAccountID == nil else { return }

        automaticBackup?.cancelPending()

        // Settings clears the working copy during explicit sign-out; the next
        // interactive sign-in rehydrates it from the new account's backup.
        if previousAccountID != nil {
            selectedTab = .home
            accountReady = false
        }
    }

    private func flushBackupWhenInactive() async {
        guard scenePhase != .active else { return }
        await flushAutomaticBackupIfNeeded()
    }

    @ViewBuilder
    private var localApp: some View {
        Group {
            if needsSetup {
                OnboardingView()
            } else {
                tabs
            }
        }
        .alert("Help improve Athevia?", isPresented: analyticsConsentPresented) {
            Button("Not Now", role: .cancel) {
                ProductAnalytics.shared.setConsent(.declined)
            }
            .accessibilityIdentifier("analytics.decline")
            Button("Share Analytics") {
                ProductAnalytics.shared.setConsent(.allowed)
            }
            .accessibilityIdentifier("analytics.allow")
        } message: {
            Text(AnalyticsPrivacyCopy.prompt)
        }
    }

    private var analyticsConsentPresented: Binding<Bool> {
        Binding(
            get: {
                (storeOutcome == .opened || hasShownStoreAlert)
                    && ProductAnalytics.shared.shouldOfferConsent
            },
            set: { isPresented in
                guard !isPresented, ProductAnalytics.shared.shouldOfferConsent else { return }
                ProductAnalytics.shared.setConsent(.declined)
            }
        )
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: RootTab.home) {
                NotificationPromptHomeView()
            }
            Tab("Plan", systemImage: "calendar", value: RootTab.plan) {
                PlanView()
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: RootTab.progress) {
                ProgressOverviewView()
            }
            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                SettingsView(
                    authentication: authentication,
                    backup: backup,
                    onLocalDataWillErase: {
                        isErasingLocalData = true
                        selectedTab = .home
                    },
                    onLocalDataDidErase: {
                        accountReady = false
                        isErasingLocalData = false
                    }
                )
            }
        }
        .task(id: automaticallyImport) {
            await autoImporter?.setEnabled(automaticallyImport)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }

            // Notification responses can arrive before the tab hierarchy exists.
            // Consume the persisted destination only once the tabs are mounted
            // and the scene is active.
            applyPendingNotificationRoute()

            // A week that has simply ended must not leave the athlete with
            // nothing to do until they happen to open the Plan tab.
            try? PlanStore(context: modelContext).advanceToCurrentWeek()
            // Refresh both Apple's Workout schedule and the native Athevia
            // Watch app cache regardless of the currently selected tab.
            await WatchScheduleSync.sync(plans.currentPlan())
            _ = WatchAppPlanSync.sync(plans.currentPlan())
            if automaticallyImport {
                await autoImporter?.importRecentWeeks()
            }
        }
        .task(id: automaticallySchedule) {
            guard scenePhase == .active, automaticallySchedule else { return }
            await WatchScheduleSync.sync(plans.currentPlan())
        }
        .task(id: watchAppFingerprint) {
            guard scenePhase == .active else { return }
            _ = WatchAppPlanSync.sync(plans.currentPlan())
        }
        .onAppear {
            applyPendingNotificationRoute()
        }
        .task(id: notificationFingerprint) {
            // This reacts to moves, skips, completions, feedback and new weeks.
            // Rebuilding local requests here keeps reminders aligned with the
            // actual plan without making every feature know about notifications.
            await TrainingNotificationManager.shared.synchronize(plans: plans)

            let highest = plans.map(\.weekNumber).max()
            if let previous = lastKnownHighestWeek,
               let highest,
               highest > previous,
               let newPlan = plans.first(where: { $0.weekNumber == highest }) {
                await TrainingNotificationManager.shared.notifyPlanReady(newPlan)
            }
            lastKnownHighestWeek = highest
        }
    }

    private func applyPendingNotificationRoute() {
        guard let route = TrainingNotificationRouteStore.consume() else { return }

        switch route {
        case .home:
            selectedTab = .home
        case .plan:
            selectedTab = .plan
        }
    }

    private var backupFingerprint: String {
        BackupSnapshot.fingerprint(
            profile: profiles.first,
            plans: plans,
            templates: templates
        ) ?? "unavailable"
    }

    private var signedInAccountID: String? {
        guard let authentication else { return nil }
        guard case .signedIn(let session) = authentication.state else { return nil }
        return session.userID
    }

    @MainActor
    private func seedAutomaticBackup(for session: AccountSession) {
        guard let automaticBackup,
              (try? LocalTrainingStoreState.hasUserData(modelContext)) == true else { return }

        automaticBackup.markDirty(
            accountID: session.userID,
            context: modelContext,
            reason: .foreground
        )
    }

    @MainActor
    private func scheduleAutomaticBackupIfNeeded() {
        guard accountReady,
              let automaticBackup,
              let accountID = signedInAccountID,
              (try? LocalTrainingStoreState.hasUserData(modelContext)) == true else { return }

        automaticBackup.markDirty(
            accountID: accountID,
            context: modelContext,
            reason: .dataChanged
        )
    }

    @MainActor
    private func flushAutomaticBackupIfNeeded() async {
        guard accountReady,
              let automaticBackup,
              let accountID = signedInAccountID else { return }

        await automaticBackup.flush(accountID: accountID, context: modelContext)
    }

    private var watchAppFingerprint: String {
        WatchAppPlanSync.fingerprint(plans.currentPlan())
    }

    private var notificationFingerprint: String {
        plans
            .flatMap(\.orderedWorkouts)
            .map { workout in
                [
                    workout.id.uuidString,
                    String(workout.date.timeIntervalSince1970),
                    workout.status.rawValue,
                    workout.feedback == nil ? "no-report" : "reported"
                ].joined(separator: ":")
            }
            .joined(separator: "|")
            + "#" + plans.map { String($0.weekNumber) }.joined(separator: ",")
    }

    private var showStoreAlert: Binding<Bool> {
        Binding(
            get: { storeOutcome != .opened && !hasShownStoreAlert },
            set: { if !$0 { hasShownStoreAlert = true } }
        )
    }

    private var storeMessage: String {
        switch storeOutcome {
        case .opened:
            ""
        case .rebuilt:
            "Athevia's database format changed, so your previous plans and reports could not be opened and have been replaced with a fresh week."
        case .inMemory:
            "Athevia could not write to storage. Anything you record now will be lost when the app closes."
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
#endif
