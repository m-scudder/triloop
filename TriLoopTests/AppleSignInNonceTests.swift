import Testing

@testable import TriLoop

@Suite("Sign in with Apple nonce")
struct AppleSignInNonceTests {
    @Test("Nonce is random-sized and hashed for Apple's request")
    func nonceShape() throws {
        let nonce = try AppleSignInNonce.make()

        #expect(nonce.rawValue.count == 32)
        #expect(nonce.sha256.count == 64)
        #expect(nonce.rawValue != nonce.sha256)
    }

    @Test("Separate sign-in requests do not reuse a nonce")
    func nonceIsNotReused() throws {
        let first = try AppleSignInNonce.make()
        let second = try AppleSignInNonce.make()

        #expect(first.rawValue != second.rawValue)
        #expect(first.sha256 != second.sha256)
    }
}
