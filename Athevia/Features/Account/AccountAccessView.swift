import SwiftData
import SwiftUI
import UIKit

/// Account entry for launch.
///
/// Athevia keeps one authenticated training context on the device. Explicit
/// sign-in replaces any stale signed-out local data with the latest backup for
/// that account before training access is restored.
struct AccountAccessView: View {
    let authentication: AuthenticationCoordinator
    let backup: BackupCoordinator
    let onReady: (AccountSession, Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var accountError: String?
    @State private var isCheckingBackup = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            switch authentication.state {
            case .checking:
                statusContent(
                    title: "Getting Athevia ready",
                    detail: "Checking your account…"
                )

            case .signedOut:
                signInContent

            case .signingIn:
                statusContent(
                    title: "Signing in",
                    detail: "Connecting securely with Apple…"
                )

            case .signedIn(let session):
                signedInContent(session)

            case .failed(let message):
                failureContent(message)
            }
        }
        .task {
            let hasLocalData = (try? LocalTrainingStoreState.hasUserData(modelContext)) == true
            let canResumeOffline = hasLocalData || TrainingResetBoundary.isFreshStartPending

            if canResumeOffline,
               let session = await authentication.resumeCachedSession() {
                // Existing local training remains immediately usable even when
                // the network is unavailable. Cloud operations can retry later.
                onReady(session, false)
                return
            }

            await authentication.refresh()
            if case .signedIn(let session) = authentication.state {
                await resolveAfterSignIn(session, replaceLocalData: false)
            }
        }
    }

    private var signInContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            VStack(spacing: 26) {
                disciplineMark

                VStack(spacing: 10) {
                    Text("Athevia")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .tracking(-1)

                    Text("Train. Learn. Adapt.")
                        .font(.title3.weight(.semibold))

                    Text("Adaptive training for running, cycling and swimming — built around what you actually do.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 360)
                }
            }

            Spacer(minLength: 44)

            AppleSignInButtonView { credential in
                let session = try await authentication.signInWithApple(credential)
                await resolveAfterSignIn(session, replaceLocalData: true)
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var disciplineMark: some View {
        HStack(spacing: 10) {
            disciplineSymbol("figure.run")
            disciplineSymbol("bicycle")
            disciplineSymbol("figure.pool.swim")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Running, cycling and swimming")
    }

    private func disciplineSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 23, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .frame(width: 58, height: 58)
            .background(.fill.tertiary, in: .circle)
    }

    @ViewBuilder
    private func signedInContent(_ session: AccountSession) -> some View {
        if isCheckingBackup {
            statusContent(
                title: "Syncing your training",
                detail: "Loading your latest backup…"
            )
        } else if let accountError {
            failureContent(accountError)
        } else {
            statusContent(
                title: "Almost there",
                detail: "Preparing your training…"
            )
        }
    }

    private func statusContent(title: String, detail: String) -> some View {
        VStack(spacing: 22) {
            disciplineMark

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView()
                .controlSize(.regular)
        }
        .padding(28)
    }

    private func failureContent(_ message: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 42, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 82, height: 82)
                    .background(.fill.tertiary, in: .circle)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Account unavailable")
                        .font(.title2.weight(.semibold))

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: 420)

            Spacer()

            Button("Try Again") {
                Task {
                    accountError = nil
                    await authentication.refresh()
                    if case .signedIn(let session) = authentication.state {
                        await resolveAfterSignIn(session, replaceLocalData: false)
                    }
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }

    @MainActor
    private func resolveAfterSignIn(
        _ session: AccountSession,
        replaceLocalData: Bool
    ) async {
        accountError = nil

        do {
            let hasLocalData = try LocalTrainingStoreState.hasUserData(modelContext)

            // Start Over is an explicit request for a new local training
            // timeline. It must survive relaunch without the persisted account
            // immediately restoring the pre-reset cloud backup.
            if TrainingResetBoundary.isFreshStartPending {
                onReady(session, false)
                return
            }

            // A persisted authenticated session keeps using the local working
            // copy. A fresh interactive sign-in always rehydrates from that
            // account's latest backup so data from a previous signed-out user
            // cannot leak into the new session.
            if !replaceLocalData, hasLocalData {
                onReady(session, false)
                return
            }

            isCheckingBackup = true
            defer { isCheckingBackup = false }

            let cloud = try await backup.latestBackup(accountID: session.userID)

            if replaceLocalData, hasLocalData {
                try LocalTrainingStoreState.removeUserData(modelContext)
            }

            if let cloud {
                try BackupRestoreService().restore(cloud.snapshot, into: modelContext)
            }

            onReady(session, false)
        } catch {
            accountError = error.localizedDescription
        }
    }
}

enum LocalTrainingStoreState {
    @MainActor
    static func hasUserData(_ context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<AthleteProfile>()) > 0
            || context.fetchCount(FetchDescriptor<WeeklyPlan>()) > 0
            || context.fetchCount(FetchDescriptor<StoredWorkoutTemplate>()) > 0
    }

    @MainActor
    static func removeUserData(_ context: ModelContext) throws {
        for plan in try context.fetch(FetchDescriptor<WeeklyPlan>()) {
            context.delete(plan)
        }
        for template in try context.fetch(FetchDescriptor<StoredWorkoutTemplate>()) {
            context.delete(template)
        }
        for profile in try context.fetch(FetchDescriptor<AthleteProfile>()) {
            context.delete(profile)
        }
        try context.save()
    }
}
