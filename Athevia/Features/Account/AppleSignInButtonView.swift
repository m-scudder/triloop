import Foundation
import AuthenticationServices
import SwiftUI

/// Native Apple authentication UI.
///
/// The button owns nonce generation and converts AuthenticationServices types
/// into Athevia's backend-neutral credential. Supabase does not belong in this
/// view.
struct AppleSignInButtonView: View {
    let signIn: @MainActor (AppleAuthenticationCredential) async throws -> Void

    @Environment(\.colorScheme) private var colorScheme
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
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(isWorking)

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(AtheviaAdaptiveStyle(.red, gaming: .danger))
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
            request.requestedScopes = [.fullName, .email]
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

            let authorizationCode = apple.authorizationCode
                .flatMap {
                    String(data: $0, encoding: .utf8)
                }
            let suggestedName = apple.fullName.flatMap {
                let value = PersonNameComponentsFormatter()
                    .string(from: $0)
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                return value.isEmpty ? nil : value
            }
            let credential = AppleAuthenticationCredential(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                nonce: activeNonce,
                suggestedName: suggestedName
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

