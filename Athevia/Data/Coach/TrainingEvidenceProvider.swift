import Foundation

/// Common boundary for future direct provider connections. The initial coach
/// uses Apple Health only; Garmin, WHOOP and Strava remain explicitly
/// unconfigured until their separate approval/terms work is complete.
enum TrainingEvidenceProviderID: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case appleHealth
    case garmin
    case whoop
    case strava
}

enum TrainingEvidenceConnectionState: String, Codable, Equatable, Sendable {
    case notConfigured
    case disconnected
    case needsAuthorization
    case connected
}

enum TrainingEvidenceIngress: Codable, Equatable, Sendable {
    case direct(provider: TrainingEvidenceProviderID)
    case appleHealthBridge(originProvider: TrainingEvidenceProviderID?)
}

struct TrainingEvidenceProvenance: Codable, Equatable, Sendable {
    let provider: TrainingEvidenceProviderID
    let ingress: TrainingEvidenceIngress
    let sourceLabel: String?
    let importedAt: Date
}

struct NormalizedTrainingEvidence: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let providerRecordID: String
    let sport: Sport
    let startDate: Date
    let endDate: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double?
    let longestContinuousSwimMeters: Double?
    let provenance: [TrainingEvidenceProvenance]

    var evidenceKind: CoachEvidenceKind { .measured }
}

protocol TrainingEvidenceProvider: Sendable {
    var providerID: TrainingEvidenceProviderID { get }

    func connectionState() async -> TrainingEvidenceConnectionState

    func fetchEvidence(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [NormalizedTrainingEvidence]

    func disconnect() async throws
}

/// Adapts already permitted Apple Health workout records without pretending the
/// original recording app is a direct provider connection.
struct AppleHealthTrainingEvidenceAdapter {
    func normalize(
        _ workout: ImportedWorkout,
        importedAt: Date = .now
    ) -> NormalizedTrainingEvidence {
        let hint = providerHint(from: workout.source)
        return NormalizedTrainingEvidence(
            id: "apple-health:\(workout.healthKitUUID.uuidString)",
            providerRecordID: workout.healthKitUUID.uuidString,
            sport: workout.sport,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationSeconds: workout.duration,
            distanceMeters: workout.distanceMeters,
            longestContinuousSwimMeters: workout.longestContinuousSwimMeters,
            provenance: [
                TrainingEvidenceProvenance(
                    provider: .appleHealth,
                    ingress: .appleHealthBridge(originProvider: hint),
                    sourceLabel: workout.source,
                    importedAt: importedAt
                )
            ]
        )
    }

    private func providerHint(from source: String?) -> TrainingEvidenceProviderID? {
        guard let source = source?.lowercased() else { return nil }
        if source.contains("garmin") { return .garmin }
        if source.contains("whoop") { return .whoop }
        if source.contains("strava") { return .strava }
        return nil
    }
}

/// Cross-source collapse is deliberately conservative. Two sessions are only
/// considered the same when one is a direct provider record and the other is
/// an Apple Health bridge explicitly attributed to that same provider, with
/// near-identical timing and metrics. Conflicting records remain separate.
enum TrainingEvidenceDeduplicator {
    static func deduplicate(_ records: [NormalizedTrainingEvidence]) -> [NormalizedTrainingEvidence] {
        var result: [NormalizedTrainingEvidence] = []

        for record in records.sorted(by: evidenceOrder) {
            if let index = result.firstIndex(where: { sameSession($0, record) }) {
                result[index] = merged(result[index], record)
            } else {
                result.append(record)
            }
        }
        return result.sorted { $0.startDate < $1.startDate }
    }

    static func sameSession(
        _ lhs: NormalizedTrainingEvidence,
        _ rhs: NormalizedTrainingEvidence
    ) -> Bool {
        if lhs.id == rhs.id {
            return true
        }

        guard lhs.sport == rhs.sport,
              let commonProvider = crossSourceProvider(lhs, rhs) else {
            return false
        }

        _ = commonProvider
        let startDelta = abs(lhs.startDate.timeIntervalSince(rhs.startDate))
        let durationDelta = abs(lhs.durationSeconds - rhs.durationSeconds)
        guard startDelta <= 30, durationDelta <= 30 else { return false }

        switch (lhs.distanceMeters, rhs.distanceMeters) {
        case (nil, nil):
            return true
        case let (left?, right?):
            let tolerance = max(50, max(left, right) * 0.01)
            return abs(left - right) <= tolerance
        default:
            // Missing and measured are not silently treated as equal because
            // that can collapse genuinely separate short sessions.
            return false
        }
    }

    private static func crossSourceProvider(
        _ lhs: NormalizedTrainingEvidence,
        _ rhs: NormalizedTrainingEvidence
    ) -> TrainingEvidenceProviderID? {
        for provider in [TrainingEvidenceProviderID.garmin, .whoop, .strava] {
            let lhsDirect = hasDirect(provider, in: lhs)
            let rhsDirect = hasDirect(provider, in: rhs)
            let lhsBridge = hasBridge(provider, in: lhs)
            let rhsBridge = hasBridge(provider, in: rhs)
            if (lhsDirect && rhsBridge) || (rhsDirect && lhsBridge) {
                return provider
            }
        }
        return nil
    }

    private static func hasDirect(
        _ provider: TrainingEvidenceProviderID,
        in record: NormalizedTrainingEvidence
    ) -> Bool {
        record.provenance.contains {
            if case .direct(let value) = $0.ingress {
                return value == provider
            }
            return false
        }
    }

    private static func hasBridge(
        _ provider: TrainingEvidenceProviderID,
        in record: NormalizedTrainingEvidence
    ) -> Bool {
        record.provenance.contains {
            if case .appleHealthBridge(let value) = $0.ingress {
                return value == provider
            }
            return false
        }
    }

    private static func merged(
        _ lhs: NormalizedTrainingEvidence,
        _ rhs: NormalizedTrainingEvidence
    ) -> NormalizedTrainingEvidence {
        let direct = [lhs, rhs].first {
            $0.provenance.contains {
                if case .direct = $0.ingress { return true }
                return false
            }
        } ?? lhs

        let provenance = Array(Set(
            (lhs.provenance + rhs.provenance).map(ProvenanceKey.init)
        )).map(\.value)

        return NormalizedTrainingEvidence(
            id: direct.id,
            providerRecordID: direct.providerRecordID,
            sport: direct.sport,
            startDate: direct.startDate,
            endDate: direct.endDate,
            durationSeconds: direct.durationSeconds,
            distanceMeters: direct.distanceMeters,
            longestContinuousSwimMeters: direct.longestContinuousSwimMeters,
            provenance: provenance.sorted { $0.importedAt < $1.importedAt }
        )
    }

    private static func evidenceOrder(
        _ lhs: NormalizedTrainingEvidence,
        _ rhs: NormalizedTrainingEvidence
    ) -> Bool {
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        return lhs.id < rhs.id
    }

    private struct ProvenanceKey: Hashable {
        let provider: TrainingEvidenceProviderID
        let ingress: String
        let sourceLabel: String?
        let importedAt: Date
        let value: TrainingEvidenceProvenance

        init(_ value: TrainingEvidenceProvenance) {
            self.value = value
            provider = value.provider
            sourceLabel = value.sourceLabel
            importedAt = value.importedAt
            switch value.ingress {
            case .direct(let provider):
                ingress = "direct:\(provider.rawValue)"
            case .appleHealthBridge(let provider):
                ingress = "apple-health:\(provider?.rawValue ?? "unknown")"
            }
        }

        static func == (lhs: ProvenanceKey, rhs: ProvenanceKey) -> Bool {
            lhs.provider == rhs.provider
                && lhs.ingress == rhs.ingress
                && lhs.sourceLabel == rhs.sourceLabel
                && lhs.importedAt == rhs.importedAt
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(provider)
            hasher.combine(ingress)
            hasher.combine(sourceLabel)
            hasher.combine(importedAt)
        }
    }
}
