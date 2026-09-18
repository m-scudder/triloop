import AuthenticationServices
import SwiftUI

/// Native Apple authentication UI.
///
/// The button owns nonce generation and converts AuthenticationServices types
/// into TriLoop's backend-neutral credential. Supabase does not belong in this
/// view.
struct AppleSignInButtonView: View {
    let signIn: @MainActor (AppleAuthenticationCredential) async throws -> Void

    @State private var activeNonce: String?
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                prepare(request)
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(isWorking)

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func prepare(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        do {
            let nonce = try AppleSignInNonce.make()
            activeNonce = nonce.rawValue
            request.nonce = nonce.sha256
            request.requestedScopes = [.email]
        } catch {
            activeNonce = nil
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription

        case .success(let authorization):
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = apple.identityToken
            else {
                errorMessage = AppleSignInPreparationError.missingIdentityToken.localizedDescription
                return
            }
            guard let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = AppleSignInPreparationError.invalidIdentityToken.localizedDescription
                return
            }

            let authorizationCode = apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let credential = AppleAuthenticationCredential(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: activeNonce
            )

            isWorking = true
            Task { @MainActor in
                defer {
                    isWorking = false
                    activeNonce = nil
                }
                do {
                    try await signIn(credential)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
