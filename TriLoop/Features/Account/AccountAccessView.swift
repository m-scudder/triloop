import SwiftData
import SwiftUI
import UIKit

/// Account entry for launch.
///
/// Existing installations are handled safely: local training is never replaced
/// by cloud data. A clean install with a cloud backup is offered restore before
/// onboarding can create competing local data.
struct AccountAccessView: View {
    let authentication: AuthenticationCoordinator
    let backup: BackupCoordinator
    let onReady: (AccountSession, Bool) -> Void
    let onContinueOffline: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var restoreCandidate: BackupEnvelope?
    @State private var accountError: String?
    @State private var isCheckingBackup = false
    @State private var hasLocalTraining = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            switch authentication.state {
            case .checking:
                statusContent(
                    title: "Getting TriLoop ready",
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
            hasLocalTraining = (try? LocalTrainingStoreState.hasUserData(modelContext)) == true
            await authentication.refresh()
            if case .signedIn(let session) = authentication.state {
                await resolveAfterSignIn(session, seedLocalBackup: false)
            }
        }
    }

    private var signInContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            VStack(spacing: 26) {
                disciplineMark

                VStack(spacing: 10) {
                    Text("TriLoop")
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

            VStack(spacing: 14) {
                AppleSignInButtonView { credential in
                    let session = try await authentication.signInWithApple(credential)
                    await resolveAfterSignIn(session, seedLocalBackup: true)
                }

                if hasLocalTraining {
                    Button("Continue on this iPhone") {
                        onContinueOffline()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                }

                Text(hasLocalTraining
                     ? "Your existing training stays on this iPhone. Sign in whenever you want cloud backup and restore."
                     : "Your training stays on this iPhone first. Signing in adds cloud backup and restore.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 360)
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
            .symbolRenderingMode(.hierarchical)
            .frame(width: 58, height: 58)
            .background(.fill.tertiary, in: .circle)
    }

    @ViewBuilder
    private func signedInContent(_ session: AccountSession) -> some View {
        if isCheckingBackup {
            statusContent(
                title: "Checking your training",
                detail: "Looking for your latest backup…"
            )
        } else if let restoreCandidate {
            restoreContent(restoreCandidate, session: session)
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

    private func restoreContent(_ envelope: BackupEnvelope, session: AccountSession) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            VStack(spacing: 14) {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .font(.system(size: 42, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 82, height: 82)
                    .background(.fill.tertiary, in: .circle)
                    .accessibilityHidden(true)

                Text("Welcome back")
                    .font(.largeTitle.weight(.bold))

                Text("We found your latest TriLoop backup.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 34)

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionEyebrow(text: "Last backup")
                        Text(envelope.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.body.weight(.medium))
                    }

                    Divider()

                    HStack(alignment: .top, spacing: 12) {
                        StatTile(
                            value: "\(envelope.snapshot.plans.count)",
                            label: envelope.snapshot.plans.count == 1 ? "Training week" : "Training weeks"
                        )

                        StatTile(
                            value: "\(completedWorkoutCount(envelope))",
                            label: "Completed"
                        )
                    }
                }
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 28)

            VStack(spacing: 12) {
                Button("Restore my training") {
                    restore(session)
                }
                .buttonStyle(PrimaryActionButtonStyle())

                Button("Sign Out", role: .cancel) {
                    Task { try? await authentication.signOut() }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: 420)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private func failureContent(_ message: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 42, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
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

            VStack(spacing: 12) {
                Button("Try Again") {
                    Task {
                        accountError = nil
                        await authentication.refresh()
                        if case .signedIn(let session) = authentication.state {
                            await resolveAfterSignIn(session, seedLocalBackup: false)
                        }
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())

                if hasLocalTraining {
                    Button("Continue on this iPhone") {
                        onContinueOffline()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }

    @MainActor
    private func resolveAfterSignIn(
        _ session: AccountSession,
        seedLocalBackup: Bool
    ) async {
        accountError = nil

        do {
            if try LocalTrainingStoreState.hasUserData(modelContext) {
                // Existing install: never replace its local store. The automatic
                // backup scheduler will attach this local history to the account.
                restoreCandidate = nil
                onReady(session, seedLocalBackup)
                return
            }

            isCheckingBackup = true
            defer { isCheckingBackup = false }

            if let cloud = try await backup.latestBackup(accountID: session.userID) {
                restoreCandidate = cloud
            } else {
                onReady(session, false)
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
                onReady(session, false)
            } catch {
                accountError = error.localizedDescription
            }
        }
    }

    private func completedWorkoutCount(_ envelope: BackupEnvelope) -> Int {
        envelope.snapshot.plans
            .flatMap(\.workouts)
            .filter { $0.status == .completed }
            .count
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
