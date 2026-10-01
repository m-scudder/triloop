import Foundation
import Testing

@testable import Athevia

@Suite("Coach athlete context")
@MainActor
struct CoachAthleteContextTests {

    @Test("Missing permission is explicit and missing evidence never becomes zero")
    func missingPermissionAndMissingEvidence() {
        let baseline = AthleteBaseline(
            running: .none,
            swimming: .none,
            cycling: .under20,
            assessedAt: CoachTestFixture.date()
        )
        let profile = CoachTestFixture.profile(
            setup: CoachTestFixture.setup(baseline: baseline)
        )
        let context = CoachTestFixture.context(
            profile: profile,
            plans: [],
            healthAccess: .denied
        )

        #expect(context.healthAccess == .denied)
        #expect(context.recentHealthWorkouts.isEmpty)
        #expect(context.caveats.contains { $0.contains("not available") })

        let running = context.capability.sports.first { $0.sport == .running }
        #expect(running?.baselineMeters == nil)
        #expect(running?.recentBestMeters == nil)
        #expect(running?.recentAverageMeters == nil)
        #expect(running?.lifetimeBestMeters == nil)
    }

    @Test("Context keeps baseline, recent evidence and lifetime best distinct")
    func evidencePrecedenceIsExplicit() {
        let now = CoachTestFixture.date()
        let oldDate = CoachTestFixture.calendar.date(
            byAdding: .day,
            value: -60,
            to: now
        )!
        let recentDate = CoachTestFixture.calendar.date(
            byAdding: .day,
            value: -7,
            to: now
        )!

        let old = CoachTestFixture.importedPlan(
            sport: .running,
            date: oldDate,
            distanceMeters: 10_000,
            weekNumber: 1
        )
        let recent = CoachTestFixture.importedPlan(
            sport: .running,
            date: recentDate,
            distanceMeters: 3_000,
            weekNumber: 2
        )
        let context = CoachTestFixture.context(
            profile: CoachTestFixture.profile(),
            plans: [old, recent],
            asOf: now
        )

        let running = context.capability.sports.first { $0.sport == .running }
        #expect(running?.baselineMeters == 5_000)
        #expect(running?.recentBestMeters == 3_000)
        #expect(running?.recentAverageMeters == 3_000)
        #expect(running?.lifetimeBestMeters == 10_000)
        #expect(running?.evidenceKind == .measured)
    }

    @Test("Swimming continuous ability is never replaced by total session distance")
    func swimmingContinuousVersusTotal() throws {
        let now = CoachTestFixture.date()
        let swimPlan = CoachTestFixture.importedPlan(
            sport: .swimming,
            date: now,
            distanceMeters: 1_000,
            longestContinuousSwimMeters: 100
        )
        let health = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .swimming,
            startDate: now,
            endDate: now.addingTimeInterval(40 * 60),
            duration: 40 * 60,
            distanceMeters: 1_000,
            longestContinuousSwimMeters: 100,
            source: "com.apple.Health"
        )

        let context = CoachTestFixture.context(
            profile: CoachTestFixture.profile(),
            plans: [swimPlan],
            healthWorkouts: [health],
            asOf: now
        )

        let swimming = context.capability.sports.first { $0.sport == .swimming }
        #expect(swimming?.recentContinuousMeters == 100)
        #expect(swimming?.recentBestMeters == 100)
        #expect(swimming?.lifetimeBestMeters == 100)

        let evidence = try #require(context.recentHealthWorkouts.first)
        #expect(evidence.distanceMeters == 1_000)
        #expect(evidence.longestContinuousSwimMeters == 100)
    }

    @Test("Context is bounded, minimized and athlete scoped")
    func boundedAndScoped() throws {
        let now = CoachTestFixture.date()
        let workouts = (0..<32).map { offset in
            let start = CoachTestFixture.calendar.date(
                byAdding: .day,
                value: -offset,
                to: now
            )!
            return ImportedWorkout(
                healthKitUUID: UUID(),
                sport: .running,
                startDate: start,
                endDate: start.addingTimeInterval(30 * 60),
                duration: 30 * 60,
                distanceMeters: Double(2_000 + offset * 10),
                source: "com.example.recorder"
            )
        }

        let first = CoachTestFixture.profile()
        let second = CoachTestFixture.profile()
        let firstContext = CoachTestFixture.context(
            profile: first,
            plans: [],
            healthWorkouts: workouts,
            asOf: now
        )
        let secondContext = CoachTestFixture.context(
            profile: second,
            plans: [],
            healthWorkouts: workouts,
            asOf: now
        )

        #expect(firstContext.recentHealthWorkouts.count == 24)
        #expect(firstContext.athleteScopeID != secondContext.athleteScopeID)

        let data = try JSONEncoder().encode(firstContext)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("route"))
        #expect(!json.contains("feedbackNote"))
        #expect(!json.contains("gps"))
    }

    @Test("Context version changes only when evidence changes")
    func stableContextVersion() {
        let profile = CoachTestFixture.profile()
        let plan = CoachTestFixture.seedPlan()
        let first = CoachTestFixture.context(
            profile: profile,
            plans: [plan],
            asOf: CoachTestFixture.date()
        )
        let basePlanVersion = CoachPlanVersion.fingerprint(plan)
        let secondTime = CoachTestFixture.date().addingTimeInterval(30)
        let second = CoachTestFixture.context(
            profile: profile,
            plans: [plan],
            asOf: secondTime
        )

        #expect(first.generatedAt != second.generatedAt)
        #expect(first.version == second.version)

        plan.generationReason = "Changed after preview"
        let changed = CoachTestFixture.context(
            profile: profile,
            plans: [plan],
            asOf: secondTime
        )
        // Generation copy alone is not evidence; plan version separately guards
        // plan mutations. Context remains tied to athlete evidence/constraints.
        #expect(first.version == changed.version)
        #expect(CoachPlanVersion.fingerprint(plan) != basePlanVersion)
    }
}

@Suite("Coach provider normalization")
@MainActor
struct CoachProviderBoundaryTests {

    private func directGarmin(
        id: String = "garmin-1",
        distance: Double = 5_000
    ) -> NormalizedTrainingEvidence {
        let start = CoachTestFixture.date()
        return NormalizedTrainingEvidence(
            id: id,
            providerRecordID: id,
            sport: .running,
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            durationSeconds: 30 * 60,
            distanceMeters: distance,
            longestContinuousSwimMeters: nil,
            provenance: [
                TrainingEvidenceProvenance(
                    provider: .garmin,
                    ingress: .direct(provider: .garmin),
                    sourceLabel: "Garmin",
                    importedAt: start
                )
            ]
        )
    }

    @Test("Apple Health bridge and direct provider duplicate collapse conservatively")
    func bridgeDeduplication() {
        let start = CoachTestFixture.date()
        let health = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            duration: 30 * 60,
            distanceMeters: 5_000,
            source: "Garmin Connect"
        )
        let bridged = AppleHealthTrainingEvidenceAdapter().normalize(
            health,
            importedAt: start
        )

        let result = TrainingEvidenceDeduplicator.deduplicate([
            directGarmin(),
            bridged
        ])

        #expect(result.count == 1)
        #expect(result[0].provenance.count == 2)
    }

    @Test("Conflicting source records are not merged")
    func conflictingRecordsRemainSeparate() {
        let start = CoachTestFixture.date()
        let health = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .running,
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            duration: 30 * 60,
            distanceMeters: 6_000,
            source: "Garmin Connect"
        )
        let bridged = AppleHealthTrainingEvidenceAdapter().normalize(
            health,
            importedAt: start
        )

        let result = TrainingEvidenceDeduplicator.deduplicate([
            directGarmin(distance: 5_000),
            bridged
        ])

        #expect(result.count == 2)
    }

    @Test("Apple Health provenance does not claim a direct connection")
    func bridgeIsNotDirectConnection() throws {
        let start = CoachTestFixture.date()
        let health = ImportedWorkout(
            healthKitUUID: UUID(),
            sport: .cycling,
            startDate: start,
            endDate: start.addingTimeInterval(60 * 60),
            duration: 60 * 60,
            distanceMeters: 20_000,
            source: "Strava"
        )
        let evidence = AppleHealthTrainingEvidenceAdapter().normalize(health)
        let provenance = try #require(evidence.provenance.first)

        #expect(provenance.provider == .appleHealth)
        if case .appleHealthBridge(let origin) = provenance.ingress {
            #expect(origin == .strava)
        } else {
            Issue.record("Apple Health import was incorrectly represented as a direct provider connection.")
        }
    }
}
