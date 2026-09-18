import Foundation
import SwiftData

enum BackupRestoreError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case localStoreNotEmpty

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "This backup uses unsupported schema version \(version)."
        case .localStoreNotEmpty:
            "This iPhone already contains TriLoop training data. Cloud data was not applied."
        }
    }
}

/// Restores only into an empty TriLoop store.
///
/// Automatic conflict merging is deliberately deferred until true multi-device
/// sync exists. A cloud backup must never silently overwrite newer local data.
@MainActor
struct BackupRestoreService {
    func restore(_ snapshot: BackupSnapshot, into context: ModelContext) throws {
        guard snapshot.schemaVersion == BackupSnapshot.currentSchemaVersion else {
            throw BackupRestoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        guard try storeIsEmpty(context) else {
            throw BackupRestoreError.localStoreNotEmpty
        }

        if let profile = snapshot.profile {
            context.insert(profile.restore())
        }

        for template in snapshot.templates {
            context.insert(template.restore())
        }

        for plan in snapshot.plans {
            context.insert(plan.restore())
        }

        try context.save()
    }

    private func storeIsEmpty(_ context: ModelContext) throws -> Bool {
        try context.fetchCount(FetchDescriptor<AthleteProfile>()) == 0
            && context.fetchCount(FetchDescriptor<WeeklyPlan>()) == 0
            && context.fetchCount(FetchDescriptor<StoredWorkoutTemplate>()) == 0
    }
}
