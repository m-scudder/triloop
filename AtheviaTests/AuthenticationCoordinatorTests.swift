import Foundation
import Testing

@testable import Athevia

@Suite("Authentication coordinator")
@MainActor
struct AuthenticationCoordinatorTests {
    @Test("Refresh restores an existing remote session")
    func restoresSession() async {
        let expected = AccountSession(userID: "user-1", email: "athlete@example.com")
        let service = AuthenticationServiceStub(session: expected)
        let coordinator = AuthenticationCoordinator(service: service)

        await coordinator.refresh()

        #expect(coordinator.state == .signedIn(expected))
    }

    @Test("Apple credential becomes the signed-in session")
    func appleSignIn() async throws {
        let expected = AccountSession(userID: "user-2")
        let service = AuthenticationServiceStub(signInResult: expected)
        let coordinator = AuthenticationCoordinator(service: service)
        let credential = AppleAuthenticationCredential(
            identityToken: "identity-token",
            authorizationCode: "authorization-code",
            nonce: "nonce"
        )

        let session = try await coordinator.signInWithApple(credential)
        let receivedCredential = await service.lastCredential

        #expect(session == expected)
        #expect(coordinator.state == .signedIn(expected))
        #expect(receivedCredential == credential)
    }

    @Test("Deleting the account clears the account state")
    func deleteAccount() async throws {
        let session = AccountSession(userID: "user-delete")
        let service = AuthenticationServiceStub(session: session)
        let coordinator = AuthenticationCoordinator(service: service)
        await coordinator.refresh()

        try await coordinator.deleteAccount()

        #expect(coordinator.state == .signedOut)
        #expect(await service.didDeleteAccount)
    }

    @Test("Sign out clears the account state")
    func signOut() async throws {
        let session = AccountSession(userID: "user-3")
        let service = AuthenticationServiceStub(session: session)
        let coordinator = AuthenticationCoordinator(service: service)
        await coordinator.refresh()

        try await coordinator.signOut()

        #expect(coordinator.state == .signedOut)
    }
}

private actor AuthenticationServiceStub: AuthenticationService {
    private var session: AccountSession?
    private let signInResult: AccountSession?
    private(set) var lastCredential: AppleAuthenticationCredential?
    private(set) var didDeleteAccount = false

    init(session: AccountSession? = nil, signInResult: AccountSession? = nil) {
        self.session = session
        self.signInResult = signInResult
    }

    func currentSession() async throws -> AccountSession? {
        session
    }

    func signInWithApple(_ credential: AppleAuthenticationCredential) async throws -> AccountSession {
        lastCredential = credential
        let result = signInResult ?? AccountSession(userID: "stub-user")
        session = result
        return result
    }

    func signOut() async throws {
        session = nil
    }

    func deleteAccount() async throws {
        didDeleteAccount = true
        session = nil
    }

    @Test("Backup failure does not prevent sign out or cleanup")
    func backupFailureDoesNotBlockSignOut() async throws {
        enum TestError: Error { case backup }
        var events: [String] = []

        try await AccountExitFlow.signOut(
            finalBackup: {
                events.append("backup")
                throw TestError.backup
            },
            remoteSignOut: {
                events.append("sign-out")
            },
            cleanup: {
                events.append("cleanup")
            }
        )

        #expect(events == ["backup", "sign-out", "cleanup"])
    }

    @Test("Authentication sign out failure does not erase local data")
    func signOutFailureDoesNotCleanup() async {
        enum TestError: Error { case signOut }
        var events: [String] = []

        do {
            try await AccountExitFlow.signOut(
                finalBackup: {
                    events.append("backup")
                },
                remoteSignOut: {
                    events.append("sign-out")
                    throw TestError.signOut
                },
                cleanup: {
                    events.append("cleanup")
                }
            )
            Issue.record("Expected sign out failure")
        } catch TestError.signOut {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(events == ["backup", "sign-out"])
    }

}
