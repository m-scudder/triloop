import Foundation

/// Stable account identity owned by the remote authentication provider.
///
/// TriLoop deliberately keeps this free of Supabase types so the training
/// domain never depends on one backend SDK.
struct AccountSession: Codable, Equatable, Sendable {
    let userID: String
    let email: String?

    init(userID: String, email: String? = nil) {
        self.userID = userID
        self.email = email
    }
}

/// The values returned by native Sign in with Apple that a backend adapter
/// needs to exchange for an authenticated session.
struct AppleAuthenticationCredential: Equatable, Sendable {
    let identityToken: String
    let authorizationCode: String?
    let nonce: String?

    init(identityToken: String, authorizationCode: String? = nil, nonce: String? = nil) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.nonce = nonce
    }
}

protocol AuthenticationService: Sendable {
    func currentSession() async throws -> AccountSession?
    func signInWithApple(_ credential: AppleAuthenticationCredential) async throws -> AccountSession
    func signOut() async throws
}

enum AuthenticationServiceError: Error, Equatable {
    case notConfigured
}

/// Used until the Supabase client is configured. Keeping an explicit adapter
/// means we can build and test backup/restore without fake production secrets.
actor UnconfiguredAuthenticationService: AuthenticationService {
    func currentSession() async throws -> AccountSession? { nil }

    func signInWithApple(_ credential: AppleAuthenticationCredential) async throws -> AccountSession {
        throw AuthenticationServiceError.notConfigured
    }

    func signOut() async throws {}
}
