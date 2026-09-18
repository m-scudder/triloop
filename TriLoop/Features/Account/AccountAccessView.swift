import SwiftData
import SwiftUI

/// The account entry point that will replace the direct onboarding launch once
/// Supabase is configured.
///
/// Existing installations are handled safely: local training wins and is
/// attached to the signed-in account. A clean install with a cloud backup is
/// offered restore before onboarding can create competing local data.
struct AccountAccessView: View {
    let authentication: AuthenticationCoordinator
    let backup: BackupCoordinator
    let onReady: (AccountSession) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var restoreCandidate: BackupEnvelope?
    @State private var accountError: String?
    @State private var isCheckingBackup = false

    var body: some View {
        NavigationStack {
            Group {
                switch authentication.state {
                case .checking:
                    ProgressView("Checking your account…")

                case .signedOut:
                    signInContent

                case .signingIn:
                    ProgressView("Signing in…")

                case .signedIn(let session):
                    signedInContent(session)

                case .failed(let message):
                    failureContent(message)
                }
            }
            .padding(24)
            .navigationTitle("TriLoop")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await authentication.refresh()
            if case .signedIn(let session) = authentication.state {
                await resolveAfterSignIn(session)
            }
        }
    }

    private var signInContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 64))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Your training, backed up")
                    .font(.title2.weight(.bold))
                Text("Sign in to protect your plans, completed workouts and reports. Training still works from this iPhone when you're offline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            AppleSignInButtonView { credential in
                let session = try await authentication.signInWithApple(credential)
                await resolveAfterSignIn(session)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func signedInContent(_ session: AccountSession) -> some View {
        if isCheckingBackup {
            ProgressView("Checking for training data…")
        } else if let restoreCandidate {
            restoreContent(restoreCandidate, session: session)
        } else if let accountError {
            failureContent(accountError)
        } else {
            ProgressView()
                .task { await resolveAfterSignIn(session) }
        }
    }

    private func restoreContent(_ envelope: BackupEnvelope, session: AccountSession) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 54))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Training data found")
                    .font(.title2.weight(.bold))
                Text(restoreSummary(envelope))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Restore my training") {
                restore(session)
            }
            .buttonStyle(PrimaryActionButtonStyle())

            Button("Sign Out", role: .cancel) {
                Task { try? await authentication.signOut() }
            }

            Spacer()
        }
    }

    private func failureContent(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Account unavailable", systemImage: "exclamationmark.icloud")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    accountError = nil
                    await authentication.refresh()
                    if case .signedIn(let session) = authentication.state {
                        await resolveAfterSignIn(session)
                    }
                }
            }
        }
    }

    @MainActor
    private func resolveAfterSignIn(_ session: AccountSession) async {
        accountError = nil

        do {
            if try LocalTrainingStoreState.hasUserData(modelContext) {
                // Existing install: never replace its local store. Once the
                // remote adapter is configured the normal backup scheduler will
                // make this account's first cloud revision.
                restoreCandidate = nil
                onReady(session)
                return
            }

            isCheckingBackup = true
            defer { isCheckingBackup = false }

            if let cloud = try await backup.latestBackup(accountID: session.userID) {
                restoreCandidate = cloud
            } else {
                onReady(session)
            }
        } catch {
            accountError = error.localizedDescription
        }
    }

    private func restore(_ session: AccountSession) {
        isCheckingBackup = true
        Task { @MainActor in
            defer { isCheckingBackup = false }
            do {
                guard try await backup.restoreLatest(
                    accountID: session.userID,
                    into: modelContext
                ) != nil else {
                    accountError = "The backup is no longer available."
                    return
                }
                restoreCandidate = nil
                onReady(session)
            } catch {
                accountError = error.localizedDescription
            }
        }
    }

    private func restoreSummary(_ envelope: BackupEnvelope) -> String {
        let weeks = envelope.snapshot.plans.count
        let completed = envelope.snapshot.plans
            .flatMap(\.workouts)
            .filter { $0.status == .completed }
            .count
        let date = envelope.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "Last backup: \(date)\n\(weeks) training \(weeks == 1 ? "week" : "weeks") · \(completed) completed workouts"
    }
}

enum LocalTrainingStoreState {
    @MainActor
    static func hasUserData(_ context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<AthleteProfile>()) > 0
            || context.fetchCount(FetchDescriptor<WeeklyPlan>()) > 0
            || context.fetchCount(FetchDescriptor<StoredWorkoutTemplate>()) > 0
    }
}
