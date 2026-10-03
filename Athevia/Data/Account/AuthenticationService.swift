import Foundation

/// Stable account identity owned by the remote authentication provider.
///
/// Athevia deliberately keeps this free of Supabase types so the training
/// domain never depends on one backend SDK.
struct AccountSession: Codable, Equatable, Sendable {
    let userID: String
    let email: String?
    /// Available when Apple supplies the person's name during the initial
    /// authorization. Later sign-ins may legitimately leave this nil.
    let suggestedName: String?

    init(
        userID: String,
        email: String? = nil,
        suggestedName: String? = nil
    ) {
        self.userID = userID
        self.email = email
        self.suggestedName = suggestedName
    }
}

/// The values returned by native Sign in with Apple that a backend adapter
/// needs to exchange for an authenticated session.
struct AppleAuthenticationCredential: Equatable, Sendable {
    let identityToken: String
    let authorizationCode: String?
    let nonce: String?
    let suggestedName: String?

    init(
        identityToken: String,
        authorizationCode: String? = nil,
        nonce: String? = nil,
        suggestedName: String? = nil
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.nonce = nonce
        self.suggestedName = suggestedName
    }
}

protocol AuthenticationService: Sendable {
    /// Returns only the locally cached auth session. This must not require
    /// network access or token refresh.
    func cachedSession() async -> AccountSession?
    func currentSession() async throws -> AccountSession?
    func signInWithApple(_ credential: AppleAuthenticationCredential) async throws -> AccountSession
    func signOut() async throws
    func deleteAccount() async throws
}

enum AuthenticationServiceError: LocalizedError, Equatable {
    case notConfigured

    var errorDescription: String? {
        "Account sign-in is not configured yet."
    }
}

/// Used until the Supabase client is configured. Keeping an explicit adapter
/// means we can build and test backup/restore without fake production secrets.
actor UnconfiguredAuthenticationService: AuthenticationService {
    func cachedSession() async -> AccountSession? { nil }
    func currentSession() async throws -> AccountSession? { nil }

    func signInWithApple(_ credential: AppleAuthenticationCredential) async throws -> AccountSession {
        throw AuthenticationServiceError.notConfigured
    }

    func signOut() async throws {}
    func deleteAccount() async throws {
        throw AuthenticationServiceError.notConfigured
    }
}
