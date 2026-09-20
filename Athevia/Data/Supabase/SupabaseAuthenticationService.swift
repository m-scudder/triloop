import Foundation
import Supabase

actor SupabaseAuthenticationService: AuthenticationService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseConfiguration.client) {
        self.client = client
    }

    func currentSession() async throws -> AccountSession? {
        guard client.auth.currentSession != nil else { return nil }
        let session = try await client.auth.session
        return AccountSession(
            userID: session.user.id.uuidString,
            email: session.user.email
        )
    }

    func signInWithApple(_ credential: AppleAuthenticationCredential) async throws -> AccountSession {
        guard let nonce = credential.nonce, !nonce.isEmpty else {
            throw SupabaseAuthenticationError.missingNonce
        }

        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: credential.identityToken,
                nonce: nonce
            )
        )

        return AccountSession(
            userID: session.user.id.uuidString,
            email: session.user.email
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}

enum SupabaseAuthenticationError: LocalizedError, Equatable {
    case missingNonce

    var errorDescription: String? {
        "Apple sign-in could not be verified because its secure nonce is missing."
    }
}
