import Foundation
import Testing

@testable import Athevia

@Suite("Authentication coordinator")
@MainActor
struct AuthenticationCoordinatorTests {
    @Test("Cached session can resume without a remote refresh")
    func resumesCachedSession() async {
        let expected = AccountSession(userID: "cached-user", email: "cached@example.com")
        let service = AuthenticationServiceStub(session: expected)
        let coordinator = AuthenticationCoordinator(service: service)

        let session = await coordinator.resumeCachedSession()

        #expect(session == expected)
        #expect(coordinator.state == .signedIn(expected))
        #expect(await service.currentSessionCalls == 0)
    }

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
            nonce: "nonce",
            suggestedName: "Mayank Agarwal"
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

    @Test("Backup failure does not prevent sign out or cleanup")
    func backupFailureDoesNotBlockSignOut() async throws {
        enum TestError: Error { case backup }
        var events: [String] = []

        await AccountExitFlow.signOut(
            finalBackup: {
                events.append("backup")
                throw TestError.backup
            },
            remoteSignOut: {
                events.append("sign-out")
            },
            localSignOutFallback: {
                events.append("local-fallback")
            },
            cleanup: {
                events.append("cleanup")
            }
        )

        #expect(events == ["backup", "sign-out", "cleanup"])
    }

    @Test("Authentication sign out failure falls back locally and still cleans up")
    func signOutFailureUsesLocalFallbackAndCleanup() async {
        enum TestError: Error { case signOut }
        var events: [String] = []

        await AccountExitFlow.signOut(
            finalBackup: {
                events.append("backup")
            },
            remoteSignOut: {
                events.append("sign-out")
                throw TestError.signOut
            },
            localSignOutFallback: {
                events.append("local-fallback")
            },
            cleanup: {
                events.append("cleanup")
            }
        )

        #expect(events == ["backup", "sign-out", "local-fallback", "cleanup"])
    }
}

private actor AuthenticationServiceStub: AuthenticationService {
    private var session: AccountSession?
    private let signInResult: AccountSession?
    private(set) var lastCredential: AppleAuthenticationCredential?
    private(set) var didDeleteAccount = false
    private(set) var currentSessionCalls = 0

    init(session: AccountSession? = nil, signInResult: AccountSession? = nil) {
        self.session = session
        self.signInResult = signInResult
    }

    func cachedSession() async -> AccountSession? {
        session
    }

    func currentSession() async throws -> AccountSession? {
        currentSessionCalls += 1
        return session
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


}
