import SwiftData
import SwiftUI

/// Account and cloud-backup controls for the authenticated Athevia account.
///
/// Sign-out changes only authentication state. RootView reacts to that state
/// transition and returns the app to the account entry screen while keeping
/// local training intact.
struct AccountBackupSettingsView: View {
    let authentication: AuthenticationCoordinator
    let backup: BackupCoordinator

    @Environment(\.modelContext) private var modelContext
    @State private var latestBackup: BackupEnvelope?
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        List {
            Section("Account") {
                switch authentication.state {
                case .signedIn(let session):
                    LabeledContent("Apple", value: session.email ?? "Signed in")

                    Button("Sign Out", role: .destructive) {
                        signOut()
                    }
                    .disabled(isWorking)

                case .checking, .signingIn:
                    HStack {
                        Text("Apple")
                        Spacer()
                        ProgressView()
                    }

                case .signedOut, .failed:
                    AppleSignInButtonView { credential in
                        _ = try await authentication.signInWithApple(credential)
                        await refreshBackup()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            if case .signedIn(let session) = authentication.state {
                Section {
                    LabeledContent("Status", value: backupStatus)
                    LabeledContent("Last Backup", value: lastBackupText)

                    Button("Back Up Now") {
                        backUpNow(session)
                    }
                    .disabled(isWorking)
                } header: {
                    Text("Cloud Backup")
                } footer: {
                    Text("Athevia keeps training on this iPhone first. Cloud backup runs separately, so losing connectivity does not stop a workout from being recorded.")
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

    private var backupStatus: String {
        switch backup.state {
        case .idle:
            latestBackup == nil ? "Not backed up" : "Safe"
        case .backingUp:
            "Backing up…"
        case .backedUp:
            "Safe"
        case .restoring:
            "Restoring…"
        case .failed:
            "Pending"
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

    private func signOut() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await authentication.signOut()
                latestBackup = nil
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
