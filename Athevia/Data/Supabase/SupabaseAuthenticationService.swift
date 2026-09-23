import Foundation
import Supabase

actor SupabaseAuthenticationService: AuthenticationService {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseConfiguration.client) {
        self.client = client
    }

    func cachedSession() async -> AccountSession? {
        guard let session = client.auth.currentSession else { return nil }
        return AccountSession(
            userID: session.user.id.uuidString,
            email: session.user.email
        )
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

    func deleteAccount() async throws {
        struct DeleteAccountResponse: Decodable {
            let deleted: Bool
        }

        let response: DeleteAccountResponse = try await client.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(method: .delete)
        )

        guard response.deleted else {
            throw SupabaseAuthenticationError.accountDeletionFailed
        }

        // Account deletion invalidates the remote identity. Clear any cached
        // local auth session so RootView immediately returns to account entry.
        try? await client.auth.signOut()
    }
}

enum SupabaseAuthenticationError: LocalizedError, Equatable {
    case missingNonce
    case accountDeletionFailed

    var errorDescription: String? {
        switch self {
        case .missingNonce:
            "Apple sign-in could not be verified because its secure nonce is missing."
        case .accountDeletionFailed:
            "Your account could not be deleted. Please try again."
        }
    }
}
