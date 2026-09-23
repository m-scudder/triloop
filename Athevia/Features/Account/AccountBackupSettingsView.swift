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
    @State private var pendingCloudBackup: BackupEnvelope?
    @State private var signedInSession: AccountSession?

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
                Section {
                    AppleSignInButtonView { credential in
                        let session = try await authentication.signInWithApple(credential)
                        await resolveNewlyConnectedAccount(session)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Connect an account to back up training from this iPhone.")
                }
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
        .confirmationDialog(
            "Cloud training already exists",
            isPresented: Binding(
                get: { pendingCloudBackup != nil },
                set: { if !$0 { pendingCloudBackup = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Keep This iPhone & Back It Up") {
                keepLocalTraining()
            }
            Button("Restore Cloud Training", role: .destructive) {
                restoreCloudTraining()
            }
            Button("Cancel", role: .cancel) {
                pendingCloudBackup = nil
                signedInSession = nil
            }
        } message: {
            Text("Choose which training history should become active on this iPhone. This avoids silently replacing local or cloud data.")
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

    @MainActor
    private func resolveNewlyConnectedAccount(_ session: AccountSession) async {
        isWorking = true
        defer { isWorking = false }

        do {
            let hasLocalData = try LocalTrainingStoreState.hasUserData(modelContext)
            let cloud = try await backup.latestBackup(accountID: session.userID)

            guard hasLocalData else {
                if let cloud {
                    try BackupRestoreService().restore(cloud.snapshot, into: modelContext)
                    latestBackup = cloud
                }
                return
            }

            guard let cloud else {
                latestBackup = try await backup.backup(
                    accountID: session.userID,
                    from: modelContext
                )
                message = "Cloud backup is now connected."
                return
            }

            pendingCloudBackup = cloud
            signedInSession = session
        } catch {
            message = "Could not connect cloud backup: \(error.localizedDescription)"
        }
    }

    private func keepLocalTraining() {
        guard let session = signedInSession else { return }
        pendingCloudBackup = nil
        signedInSession = nil
        backUpNow(session)
    }

    private func restoreCloudTraining() {
        guard let cloud = pendingCloudBackup else { return }
        pendingCloudBackup = nil
        signedInSession = nil

        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try LocalTrainingStoreState.removeUserData(modelContext)
                try BackupRestoreService().restore(cloud.snapshot, into: modelContext)
                latestBackup = cloud
                message = "Cloud training restored on this iPhone."
            } catch {
                message = "Could not restore cloud training: \(error.localizedDescription)"
            }
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
