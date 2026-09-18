import Foundation
import Testing

@testable import TriLoop

@Suite("Supabase backup mapping")
struct SupabaseBackupRepositoryTests {
    @Test("Backup revision row preserves a snapshot")
    func revisionRowRoundTrip() throws {
        let profile = AthleteProfileBackup(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Athlete",
            experienceLevel: .beginner,
            trainingStartDate: Date(timeIntervalSince1970: 1_780_000_000),
            poolLengthMeters: 25,
            usesMetricUnits: true,
            setup: nil
        )
        let snapshot = BackupSnapshot(
            createdAt: Date(timeIntervalSince1970: 1_780_100_000),
            profile: profile,
            plans: [],
            templates: []
        )
        let accountID = "22222222-2222-2222-2222-222222222222"
        let revisionID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let envelope = BackupEnvelope(
            revisionID: revisionID,
            accountID: accountID,
            createdAt: Date(timeIntervalSince1970: 1_780_200_000),
            snapshot: snapshot
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let row = try SupabaseBackupRevisionRow(envelope, encoder: encoder)
        let restored = try row.envelope(decoder: decoder)

        #expect(restored.revisionID == revisionID)
        #expect(restored.accountID.lowercased() == accountID)
        #expect(restored.snapshot.profile?.name == "Athlete")
        #expect(restored.snapshot.schemaVersion == BackupSnapshot.currentSchemaVersion)
    }

    @Test("Non UUID account IDs are rejected before reaching Supabase")
    func rejectsInvalidAccountID() throws {
        let snapshot = BackupSnapshot(profile: nil, plans: [], templates: [])
        let envelope = BackupEnvelope(accountID: "not-a-uuid", snapshot: snapshot)
        let encoder = JSONEncoder()

        do {
            _ = try SupabaseBackupRevisionRow(envelope, encoder: encoder)
            Issue.record("Expected invalid account ID")
        } catch let error as SupabaseBackupRepositoryError {
            #expect(error == .invalidAccountID)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
