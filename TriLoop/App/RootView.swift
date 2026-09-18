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
    @AppStorage("automaticallyImportWorkouts") private var automaticallyImport = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    /// Setup state is asked of the profile rather than inferred from whether a
    /// plan exists: an athlete migrated from an earlier build has plans but has
    /// never been asked anything.
    private var needsSetup: Bool {
        profiles.first?.hasCompletedSetup != true
    }

    var body: some View {
        Group {
            if let authentication, let backup, !accountReady {
                AccountAccessView(
                    authentication: authentication,
                    backup: backup,
                    onReady: { session, seedLocalBackup in
                        accountReady = true
                        if seedLocalBackup {
                            seedAutomaticBackup(for: session)
                        }
                    },
                    onContinueOffline: { accountReady = true }
                )
            } else {
                localApp
            }
        }
        .onChange(of: backupFingerprint) { _, _ in
            scheduleAutomaticBackupIfNeeded()
        }
        .onChange(of: signedInAccountID) { _, newAccountID in
            if newAccountID == nil {
                automaticBackup?.cancelPending()
            }
        }
        .task(id: scenePhase) {
            guard scenePhase != .active else { return }
            await flushAutomaticBackupIfNeeded()
        }
        .alert("Training data was reset", isPresented: showStoreAlert) {
            Button("OK", role: .cancel) { hasShownStoreAlert = true }
        } message: {
            Text(storeMessage)
        }
    }

    @ViewBuilder
    private var localApp: some View {
        if needsSetup {
            OnboardingView()
        } else {
            tabs
        }
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
                SettingsView(authentication: authentication, backup: backup)
            }
        }
        .task(id: automaticallyImport) {
            await autoImporter?.setEnabled(automaticallyImport)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // A week that has simply ended must not leave the athlete with
            // nothing to do until they happen to open the Plan tab.
            try? PlanStore(context: modelContext).advanceToCurrentWeek()
            if automaticallyImport {
                await autoImporter?.importRecentWeeks()
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .triLoopNotificationRoute)) { note in
            guard let raw = note.object as? String,
                  let route = TrainingNotificationRoute(rawValue: raw) else { return }
            switch route {
            case .home: selectedTab = .home
            case .plan: selectedTab = .plan
            }
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
            "TriLoop's database format changed, so your previous plans and reports could not be opened and have been replaced with a fresh week."
        case .inMemory:
            "TriLoop could not write to storage. Anything you record now will be lost when the app closes."
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}
#endif
