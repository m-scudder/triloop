import Foundation
import Testing

@testable import TriLoop

@Suite("Supabase backup mapping")
struct SupabaseBackupRepositoryTests {
    @Test("Backup revision row preserves a snapshot")
    func revisionRowRoundTrip() throws {
        let accountID = "22222222-2222-2222-2222-222222222222"
        let revisionID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let snapshot = BackupSnapshot(
            createdAt: Date(timeIntervalSince1970: 1_780_100_000),
            profile: nil,
            plans: [],
            templates: []
        )
        let envelope = BackupEnvelope(
            revisionID: revisionID,
            accountID: accountID,
            createdAt: Date(timeIntervalSince1970: 1_780_200_000),
            snapshot: snapshot
        )

        let row = try SupabaseBackupRevisionRow(envelope)
        let restored = row.envelope

        #expect(restored.revisionID == revisionID)
        #expect(restored.accountID.lowercased() == accountID)
        #expect(restored.snapshot.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(restored.snapshot.plans.isEmpty)
    }

    @Test("Non UUID account IDs are rejected before reaching Supabase")
    func rejectsInvalidAccountID() throws {
        let snapshot = BackupSnapshot(profile: nil, plans: [], templates: [])
        let envelope = BackupEnvelope(accountID: "not-a-uuid", snapshot: snapshot)

        do {
            _ = try SupabaseBackupRevisionRow(envelope)
            Issue.record("Expected invalid account ID")
        } catch let error as SupabaseBackupRepositoryError {
            #expect(error == .invalidAccountID)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
