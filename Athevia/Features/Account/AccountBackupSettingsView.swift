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

    var body: some View {
        List {
            switch authentication.state {
            case .signedIn(let session):
                LabeledContent("Backup", value: lastBackupText)

                Button("Back Up Now") {
                    backUpNow(session)
                }
                .disabled(isWorking)

            case .checking, .signingIn:
                HStack {
                    Text("Account")
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
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
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

    private var lastBackupText: String {
        switch backup.state {
        case .backedUp(_, let date):
            TrainingFormatter.shortDateTime(date, includeYear: true)
        default:
            latestBackup.map { TrainingFormatter.shortDateTime($0.createdAt, includeYear: true) } ?? "Never"
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

}
