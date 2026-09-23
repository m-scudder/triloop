import Foundation
import Observation

enum AuthenticationCoordinatorState: Equatable {
    case checking
    case signedOut
    case signedIn(AccountSession)
    case signingIn
    case failed(String)
}

/// App-facing authentication state machine.
///
/// Native Sign in with Apple creates the credential; the future Supabase
/// adapter implements `AuthenticationService`. Neither concern leaks into the
/// training domain.
@MainActor
@Observable
final class AuthenticationCoordinator {
    private let service: any AuthenticationService

    private(set) var state: AuthenticationCoordinatorState = .checking

    init(service: any AuthenticationService) {
        self.service = service
    }

    /// Resumes the locally cached identity without contacting the network.
    /// Used only when this device already owns local training data, so an
    /// offline launch never skips account isolation on a fresh install.
    func resumeCachedSession() async -> AccountSession? {
        guard let session = await service.cachedSession() else { return nil }
        state = .signedIn(session)
        return session
    }

    func refresh() async {
        state = .checking
        do {
            if let session = try await service.currentSession() {
                state = .signedIn(session)
            } else {
                state = .signedOut
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func signInWithApple(_ credential: AppleAuthenticationCredential) async throws -> AccountSession {
        state = .signingIn
        do {
            let session = try await service.signInWithApple(credential)
            state = .signedIn(session)
            return session
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func signOut() async throws {
        do {
            try await service.signOut()
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func deleteAccount() async throws {
        do {
            try await service.deleteAccount()
            state = .signedOut
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }
}


/// Orchestrates the security-sensitive order of operations when leaving an account.
///
/// The final backup is intentionally best-effort: a connectivity failure must not
/// prevent sign-out. Local account data is only cleared after the authentication
/// provider confirms that the local session has been signed out.
@MainActor
enum AccountExitFlow {
    static func signOut(
        finalBackup: @MainActor () async throws -> Void,
        remoteSignOut: @MainActor () async throws -> Void,
        cleanup: @MainActor () async -> Void
    ) async throws {
        try? await finalBackup()
        try await remoteSignOut()
        await cleanup()
    }
}
