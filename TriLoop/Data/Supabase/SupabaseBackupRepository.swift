import Foundation
import Supabase

/// Supabase implementation of TriLoop's cloud revision store.
///
/// A revision is immutable. RLS owns authorization: the client supplies the
/// authenticated user's UUID, and PostgreSQL rejects cross-user access.
actor SupabaseBackupRepository: BackupRepository {
    private let client: SupabaseClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(client: SupabaseClient = SupabaseConfiguration.client) {
        self.client = client

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func upload(_ envelope: BackupEnvelope) async throws {
        let row = try BackupRevisionRow(envelope, encoder: encoder)
        try await client
            .from("backup_revisions")
            .insert(row)
            .execute()
    }

    func latest(for accountID: String) async throws -> BackupEnvelope? {
        guard let userID = UUID(uuidString: accountID) else {
            throw SupabaseBackupRepositoryError.invalidAccountID
        }

        let rows: [BackupRevisionRow] = try await client
            .from("backup_revisions")
            .select()
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return try rows.first?.envelope(decoder: decoder)
    }
}

enum SupabaseBackupRepositoryError: LocalizedError, Equatable {
    case invalidAccountID
    case invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .invalidAccountID:
            "The signed-in account identifier is invalid."
        case .invalidSnapshot:
            "The cloud backup could not be decoded."
        }
    }
}

private struct BackupRevisionRow: Codable, Sendable {
    let id: UUID
    let userID: UUID
    let schemaVersion: Int
    let snapshot: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case schemaVersion = "schema_version"
        case snapshot
        case createdAt = "created_at"
    }

    init(_ envelope: BackupEnvelope, encoder: JSONEncoder) throws {
        guard let userID = UUID(uuidString: envelope.accountID) else {
            throw SupabaseBackupRepositoryError.invalidAccountID
        }

        let data = try encoder.encode(envelope.snapshot)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SupabaseBackupRepositoryError.invalidSnapshot
        }

        id = envelope.revisionID
        self.userID = userID
        schemaVersion = envelope.snapshot.schemaVersion
        snapshot = json
        createdAt = envelope.createdAt
    }

    func envelope(decoder: JSONDecoder) throws -> BackupEnvelope {
        guard let data = snapshot.data(using: .utf8) else {
            throw SupabaseBackupRepositoryError.invalidSnapshot
        }
        let decoded = try decoder.decode(BackupSnapshot.self, from: data)
        return BackupEnvelope(
            revisionID: id,
            accountID: userID.uuidString,
            createdAt: createdAt,
            snapshot: decoded
        )
    }
}
