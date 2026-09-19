import Testing

@testable import TriLoop

@Suite("Automatic backup scheduling")
struct AutomaticBackupControllerTests {
    @Test("Retry policy uses bounded increasing delays")
    func retryPolicy() {
        let policy = BackupRetryPolicy(delays: [5, 15, 60])

        #expect(policy.delay(afterFailedAttempt: 0) == 5)
        #expect(policy.delay(afterFailedAttempt: 1) == 15)
        #expect(policy.delay(afterFailedAttempt: 2) == 60)
        #expect(policy.delay(afterFailedAttempt: 3) == nil)
    }
}
