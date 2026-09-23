import SwiftData
import SwiftUI

/// Account and cloud-backup controls for the authenticated Athevia account.
struct AccountBackupSettingsView: View {
    let authentication: AuthenticationCoordinator
    let backup: BackupCoordinator

    @Environment(\.modelContext) private var modelContext
    @State private var latestBackup: BackupEnvelope?
    @State private var isWorking = false
    @State private var message: String?
    @State private var showsDeleteConfirmation = false

    var body: some View {
        List {
            switch authentication.state {
            case .signedIn(let session):
                Section {
                    LabeledContent("Backup", value: lastBackupText)

                    Button("Back Up Now") {
                        backUpNow(session)
                    }
                    .disabled(isWorking)
                }

                Section {
                    Button("Sign Out") {
                        signOut(session)
                    }
                    .disabled(isWorking)

                    Button("Delete Account", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                    .disabled(isWorking)
                }

            case .checking, .signingIn:
                Section {
                    HStack {
                        Text("Account")
                        Spacer()
                        ProgressView()
                    }
                }

            case .signedOut, .failed:
                Section {
                    AppleSignInButtonView { credential in
                        _ = try await authentication.signInWithApple(credential)
                        await refreshBackup()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Account & Backup")
        .task {
            if case .checking = authentication.state {
                await authentication.refresh()
            }
            if case .signedIn = authentication.state {
                await refreshBackup()
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
            "Cloud Backup",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var lastBackupText: String {
        switch backup.state {
        case .backedUp(_, let date):
            date.formatted(date: .abbreviated, time: .shortened)
        default:
            latestBackup?.createdAt.formatted(date: .abbreviated, time: .shortened) ?? "Never"
        }
    }

    private func refreshBackup() async {
        guard case .signedIn(let session) = authentication.state else {
            latestBackup = nil
            return
        }

        do {
            latestBackup = try await backup.latestBackup(accountID: session.userID)
        } catch {
            // Status inspection should not turn Settings into an error screen.
            // A later explicit backup action will surface a useful error.
        }
    }

    private func backUpNow(_ session: AccountSession) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                latestBackup = try await backup.backup(
                    accountID: session.userID,
                    from: modelContext
                )
                message = "Your Athevia training is backed up."
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func deleteAccount() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await authentication.deleteAccount()
                latestBackup = nil
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func signOut(_ session: AccountSession) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                // Preserve all local changes before removing the signed-in
                // working copy. If backup fails, sign-out is cancelled rather
                // than silently discarding training.
                latestBackup = try await backup.backup(
                    accountID: session.userID,
                    from: modelContext
                )
                try await authentication.signOut()
                try LocalTrainingStoreState.removeUserData(modelContext)
                latestBackup = nil
            } catch {
                message = "Sign out was not completed: \(error.localizedDescription)"
            }
        }
    }
}
