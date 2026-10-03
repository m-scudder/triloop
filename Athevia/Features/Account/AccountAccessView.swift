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
    @State private var pendingProfileSession: AccountSession?
    @State private var pendingProfileSeedsBackup = false

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
            let hasLocalData =
                (try? LocalTrainingStoreState
                    .hasUserData(modelContext)) == true

            // Athevia always requires an account. Existing authenticated local
            // training may resume from its cached identity, but a fresh install
            // must verify the session so its cloud backup can be restored.
            if hasLocalData,
               let session = await authentication.resumeCachedSession() {
                prepareAccountEntry(
                    session,
                    seedLocalBackup: false
                )
                return
            }

            await authentication.refresh()
            if case .signedIn(let session) = authentication.state {
                await resolveAfterSignIn(
                    session,
                    replaceLocalData: false
                )
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
                        .font(.title3.weight(.semibold))                }
            }

            Spacer(minLength: 44)

            VStack(spacing: 12) {
                AppleSignInButtonView { credential in
                    let session = try await authentication
                        .signInWithApple(credential)
                    await resolveAfterSignIn(
                        session,
                        replaceLocalData: true
                    )
                }
                .frame(maxWidth: 420)            }

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var disciplineMark: some View {
        HStack(spacing: 10) {
            disciplineSymbol("figure.run", tint: Discipline.running.tint)
            disciplineSymbol("bicycle", tint: Discipline.cycling.tint)
            disciplineSymbol("figure.pool.swim", tint: Discipline.swimming.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Running, cycling and swimming")
    }

    private func disciplineSymbol(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 23, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: 58, height: 58)
            .background(tint.opacity(0.12), in: .circle)
    }

    @ViewBuilder
    private func signedInContent(_ session: AccountSession) -> some View {
        if let pendingProfileSession {
            AccountProfileSetupView(
                initialName: AccountProfileDetailsStore
                    .initialName(
                        session: pendingProfileSession,
                        in: modelContext
                    ),
                initialBirthDate: AccountProfileDetailsStore
                    .initialBirthDate(in: modelContext)
            ) { name, birthDate in
                saveProfileDetails(
                    name: name,
                    birthDate: birthDate,
                    session: pendingProfileSession
                )
            }
        } else if isCheckingBackup {
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
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
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
                    .background(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface), in: .circle)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Cloud unavailable")
                        .font(.title2.weight(.semibold))

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: 420)

            Spacer()

            VStack(spacing: 12) {
                Button("Try Again") {
                    Task {
                        accountError = nil
                        await authentication.refresh()
                        if case .signedIn(let session) = authentication.state {
                            await resolveAfterSignIn(
                                session,
                                replaceLocalData: false
                            )
                        }
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .frame(maxWidth: 420)

                Text("An account is required to use Athevia.")
                    .font(.caption)
                    .foregroundStyle(
                        AtheviaAdaptiveStyle(
                            .secondary,
                            gaming: .secondaryText
                        )
                    )
            }
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
                prepareAccountEntry(
                    session,
                    seedLocalBackup: false
                )
                return
            }

            // A persisted authenticated session keeps using the local working
            // copy. A fresh interactive sign-in always rehydrates from that
            // account's latest backup so data from a previous signed-out user
            // cannot leak into the new session.
            if !replaceLocalData, hasLocalData {
                prepareAccountEntry(
                    session,
                    seedLocalBackup: false
                )
                return
            }

            isCheckingBackup = true
            defer { isCheckingBackup = false }

            let cloud = try await backup.latestBackup(
                accountID: session.userID
            )

            if let cloud {
                if replaceLocalData, hasLocalData {
                    try LocalTrainingStoreState
                        .removeUserData(modelContext)
                }

                try BackupRestoreService()
                    .restore(cloud.snapshot, into: modelContext)
                prepareAccountEntry(
                    session,
                    seedLocalBackup: false
                )
                return
            }

            // Migration for users who previously trained without an account:
            // keep their existing local training on first required sign-in and
            // immediately seed that data into this account's cloud backup.
            prepareAccountEntry(
                session,
                seedLocalBackup:
                    replaceLocalData && hasLocalData
            )
        } catch {
            accountError = error.localizedDescription
        }
    }


    @MainActor
    private func prepareAccountEntry(
        _ session: AccountSession,
        seedLocalBackup: Bool
    ) {
        accountError = nil

        guard AccountProfileDetailsStore
            .requiresConfirmation(in: modelContext) else {
            onReady(session, seedLocalBackup)
            return
        }

        pendingProfileSeedsBackup = seedLocalBackup
        pendingProfileSession = session
    }

    @MainActor
    private func saveProfileDetails(
        name: String,
        birthDate: Date,
        session: AccountSession
    ) {
        do {
            try AccountProfileDetailsStore.save(
                name: name,
                birthDate: birthDate,
                in: modelContext
            )

            ProductAnalytics.shared.updateAccount(
                session.userID,
                email: session.email,
                name: name
            )

            let seedLocalBackup =
                pendingProfileSeedsBackup
            pendingProfileSession = nil
            pendingProfileSeedsBackup = false
            onReady(session, seedLocalBackup)
        } catch {
            pendingProfileSession = nil
            pendingProfileSeedsBackup = false
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

