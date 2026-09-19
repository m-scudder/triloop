import Foundation
import Supabase

/// Supabase implementation of TriLoop's cloud revision store.
///
/// A revision is immutable. RLS owns authorization: the client supplies the
/// authenticated user's UUID, and PostgreSQL rejects cross-user access.
actor SupabaseBackupRepository: BackupRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseConfiguration.client) {
        self.client = client
    }

    func upload(_ envelope: BackupEnvelope) async throws {
        let row = try SupabaseBackupRevisionRow(envelope)
        try await client
            .from("backup_revisions")
            .insert(row)
            .execute()
    }

    func latest(for accountID: String) async throws -> BackupEnvelope? {
        guard let userID = UUID(uuidString: accountID) else {
            throw SupabaseBackupRepositoryError.invalidAccountID
        }

        let rows: [SupabaseBackupRevisionRow] = try await client
            .from("backup_revisions")
            .select()
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return rows.first?.envelope
    }
}

enum SupabaseBackupRepositoryError: LocalizedError, Equatable {
    case invalidAccountID

    var errorDescription: String? {
        "The signed-in account identifier is invalid."
    }
}

/// Wire representation of one immutable cloud backup.
///
/// Keeping `snapshot` as a Codable value makes PostgreSQL store a real JSONB
/// object rather than an opaque JSON string, so the data remains inspectable
/// and can evolve toward normalized tables without changing the local domain.
struct SupabaseBackupRevisionRow: Codable, Sendable {
    let id: UUID
    let userID: UUID
    let schemaVersion: Int
    let snapshot: BackupSnapshot
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case schemaVersion = "schema_version"
        case snapshot
        case createdAt = "created_at"
    }

    init(_ envelope: BackupEnvelope) throws {
        guard let userID = UUID(uuidString: envelope.accountID) else {
            throw SupabaseBackupRepositoryError.invalidAccountID
        }

        id = envelope.revisionID
        self.userID = userID
        schemaVersion = envelope.snapshot.schemaVersion
        snapshot = envelope.snapshot
        createdAt = envelope.createdAt
    }

    var envelope: BackupEnvelope {
        BackupEnvelope(
            revisionID: id,
            accountID: userID.uuidString,
            createdAt: createdAt,
            snapshot: snapshot
        )
    }
}
