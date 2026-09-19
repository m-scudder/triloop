import Foundation
import Observation
import SwiftData

/// One atomically committed cloud revision.
///
/// The future Supabase implementation can write the normalized snapshot across
/// several tables and only publish this revision after every upsert succeeds.
struct BackupEnvelope: Codable, Sendable {
    let revisionID: UUID
    let accountID: String
    let createdAt: Date
    let snapshot: BackupSnapshot

    init(
        revisionID: UUID = UUID(),
        accountID: String,
        createdAt: Date = .now,
        snapshot: BackupSnapshot
    ) {
        self.revisionID = revisionID
        self.accountID = accountID
        self.createdAt = createdAt
        self.snapshot = snapshot
    }
}

protocol BackupRepository: Sendable {
    func upload(_ envelope: BackupEnvelope) async throws
    func latest(for accountID: String) async throws -> BackupEnvelope?
}

enum BackupRepositoryError: LocalizedError, Equatable {
    case notConfigured

    var errorDescription: String? {
        "Cloud backup is not configured yet."
    }
}

actor UnconfiguredBackupRepository: BackupRepository {
    func upload(_ envelope: BackupEnvelope) async throws {
        throw BackupRepositoryError.notConfigured
    }

    func latest(for accountID: String) async throws -> BackupEnvelope? {
        throw BackupRepositoryError.notConfigured
    }
}

enum BackupCoordinatorState: Equatable {
    case idle
    case backingUp
    case backedUp(revisionID: UUID, at: Date)
    case restoring
    case failed(String)
}

/// Coordinates local capture and remote persistence without making SwiftData
/// depend on a network connection.
///
/// Supabase is only the repository implementation; it is never on the critical
/// path for completing a workout.
@MainActor
@Observable
final class BackupCoordinator {
    private let repository: any BackupRepository
    private let restoreService: BackupRestoreService

    private(set) var state: BackupCoordinatorState = .idle

    init(
        repository: any BackupRepository,
        restoreService: BackupRestoreService? = nil
    ) {
        self.repository = repository
        self.restoreService = restoreService ?? BackupRestoreService()
    }

    /// Reads backup metadata/content without mutating the local store. The
    /// account entry flow uses this to decide whether restore should be offered.
    func latestBackup(accountID: String) async throws -> BackupEnvelope? {
        try await repository.latest(for: accountID)
    }

    @discardableResult
    func backup(
        accountID: String,
        from context: ModelContext,
        at date: Date = .now
    ) async throws -> BackupEnvelope {
        state = .backingUp
        do {
            let snapshot = try BackupSnapshot.capture(from: context, at: date)
            let envelope = BackupEnvelope(
                accountID: accountID,
                createdAt: date,
                snapshot: snapshot
            )
            try await repository.upload(envelope)
            state = .backedUp(revisionID: envelope.revisionID, at: date)
            return envelope
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    @discardableResult
    func restoreLatest(
        accountID: String,
        into context: ModelContext
    ) async throws -> BackupEnvelope? {
        state = .restoring
        do {
            guard let envelope = try await repository.latest(for: accountID) else {
                state = .idle
                return nil
            }
            try restoreService.restore(envelope.snapshot, into: context)
            state = .backedUp(revisionID: envelope.revisionID, at: envelope.createdAt)
            return envelope
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }
}
