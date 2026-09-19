import CryptoKit
import Foundation
import Security

enum AppleSignInPreparationError: LocalizedError, Equatable {
    case nonceGenerationFailed
    case missingIdentityToken
    case invalidIdentityToken

    var errorDescription: String? {
        switch self {
        case .nonceGenerationFailed:
            "Athevia could not prepare a secure Apple sign-in request."
        case .missingIdentityToken, .invalidIdentityToken:
            "Apple did not return a valid identity token."
        }
    }
}

struct AppleSignInNonce: Equatable, Sendable {
    let rawValue: String
    let sha256: String

    static func make(length: Int = 32) throws -> AppleSignInNonce {
        precondition(length > 0)

        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var random = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            throw AppleSignInPreparationError.nonceGenerationFailed
        }

        let raw = String(random.map { characters[Int($0) % characters.count] })
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hashed = digest.map { String(format: "%02x", $0) }.joined()
        return AppleSignInNonce(rawValue: raw, sha256: hashed)
    }
}
