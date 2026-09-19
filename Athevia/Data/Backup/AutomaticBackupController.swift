import Foundation
import Observation
import SwiftData

enum BackupTriggerReason: String, Sendable {
    case profileChanged
    case planChanged
    case workoutCompleted
    case feedbackSaved
    case recoverySaved
    case recordedWorkoutSaved
    case foreground
    case dataChanged
    case manual
}

struct BackupRetryPolicy: Equatable, Sendable {
    let delays: [TimeInterval]

    init(delays: [TimeInterval] = [5, 15, 60]) {
        self.delays = delays
    }

    func delay(afterFailedAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 0, attempt < delays.count else { return nil }
        return delays[attempt]
    }
}

/// Coalesces local mutations into cloud backups.
///
/// This is MainActor-bound because SwiftData's ModelContext is MainActor-bound.
/// A pending backup is cancelled and replaced when more local data changes, so
/// a burst of model saves becomes one complete revision rather than many tiny
/// uploads.
@MainActor
@Observable
final class AutomaticBackupController {
    private let coordinator: BackupCoordinator
    private let debounceSeconds: TimeInterval
    private let retryPolicy: BackupRetryPolicy

    private var pendingTask: Task<Void, Never>?
    private(set) var isDirty = false
    private(set) var lastTrigger: BackupTriggerReason?

    init(
        coordinator: BackupCoordinator,
        debounceSeconds: TimeInterval = 15,
        retryPolicy: BackupRetryPolicy = BackupRetryPolicy()
    ) {
        self.coordinator = coordinator
        self.debounceSeconds = debounceSeconds
        self.retryPolicy = retryPolicy
    }

    func markDirty(
        accountID: String,
        context: ModelContext,
        reason: BackupTriggerReason
    ) {
        isDirty = true
        lastTrigger = reason
        pendingTask?.cancel()

        let delay = debounceSeconds
        pendingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await runBackup(accountID: accountID, context: context)
        }
    }

    func flush(accountID: String, context: ModelContext) async {
        pendingTask?.cancel()
        pendingTask = nil
        guard isDirty else { return }
        await runBackup(accountID: accountID, context: context)
    }

    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }

    private func runBackup(accountID: String, context: ModelContext) async {
        var failedAttempt = 0

        while !Task.isCancelled {
            do {
                try await coordinator.backup(accountID: accountID, from: context)
                isDirty = false
                pendingTask = nil
                return
            } catch {
                guard let retryDelay = retryPolicy.delay(afterFailedAttempt: failedAttempt) else {
                    pendingTask = nil
                    return
                }
                failedAttempt += 1
                try? await Task.sleep(for: .seconds(retryDelay))
            }
        }
    }
}
