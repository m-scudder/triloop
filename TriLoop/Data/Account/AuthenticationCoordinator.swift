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
}
