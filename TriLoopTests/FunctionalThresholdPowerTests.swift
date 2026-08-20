import Foundation
import Testing
@testable import TriLoop

/// §6: FTP is a standing athlete value, so it needs its own query and its own
/// missing state. Absent must never read as zero watts.
@Suite("Functional threshold power")
struct FunctionalThresholdPowerTests {

    @Test("An athlete with a meter reports watts")
    func available() async throws {
        var provider = StubHealthDataProvider()
        provider.ftp = 240

        #expect(try await provider.functionalThresholdPower() == 240)
    }

    @Test("No recorded FTP is nil, not zero")
    func unavailable() async throws {
        let provider = StubHealthDataProvider()
        let ftp = try await provider.functionalThresholdPower()

        #expect(ftp == nil)
        // The trap: a rider without a meter must not appear to have 0 W.
        #expect(ftp != 0)
    }

    @Test("Without authorization the query fails rather than reporting nothing")
    func permissionUnavailable() async {
        var provider = StubHealthDataProvider()
        provider.status = .denied

        await #expect(throws: HealthDataError.notAuthorized) {
            _ = try await provider.functionalThresholdPower()
        }
    }

    #if DEBUG
    @Test("Fixtures with a power meter report FTP")
    func simulatedWithPower() async throws {
        let provider = SimulatedHealthDataProvider(
            dataset: .powerCyclist,
            referenceDate: Date(timeIntervalSince1970: 1_760_000_000)
        )
        let ftp = try await provider.functionalThresholdPower()
        #expect(ftp != nil)
    }

    @Test("Fixtures without a power meter report none")
    func simulatedWithoutPower() async throws {
        let provider = SimulatedHealthDataProvider(
            dataset: .missingPower,
            referenceDate: Date(timeIntervalSince1970: 1_760_000_000)
        )
        #expect(try await provider.functionalThresholdPower() == nil)
    }

    @Test("Cycling analysis works without FTP")
    func cyclingDoesNotRequireFTP() {
        // §6: FTP must never be required for cycling intelligence.
        let anchor = Date(timeIntervalSince1970: 1_760_000_000)
        let rides = (0..<3).map { week in
            LoadedSession(
                date: anchor.addingTimeInterval(Double(week * 7) * 86_400),
                sport: .cycling,
                durationSeconds: 3_600,
                distanceMeters: 24_000
            )
        }

        #expect(CyclingTrends.speed(rides, anchoredTo: anchor).isAvailable)
        #expect(!CyclingTrends.power(rides, anchoredTo: anchor).isAvailable)
    }
    #endif
}
