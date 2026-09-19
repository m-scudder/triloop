import Foundation
import MapKit
import Testing
@testable import TriLoop

@MainActor
@Suite("Workout sharing evidence and GPS geometry")
struct WorkoutSharingTests {
    @Test("Manual completion never shares prescription as recorded evidence")
    func manualCompletion() {
        let workout = PlannedWorkout(date: .now, discipline: .running, title: "Easy run",
                                     prescribedDurationSeconds: 1800, targetDistanceMeters: 5000,
                                     status: .completed)
        let snapshot = WorkoutShareSnapshot(workout: workout)
        #expect(snapshot.durationText == nil)
        #expect(snapshot.distanceText == nil)
        #expect(snapshot.paceOrSpeed == nil)
    }

    @Test("Recorded time retains seconds and pace uses actual distance")
    func recordedEvidence() {
        let snapshot = share(discipline: .running, duration: 1805, distance: 5000)
        #expect(snapshot.durationText == "30:05")
        #expect(snapshot.distanceText == "5.00")
        #expect(snapshot.paceOrSpeed == "6:01")
    }

    @Test("Swimming uses pace per 100 metres and cycling uses kilometres per hour")
    func sportUnits() {
        let swim = share(discipline: .swimming, duration: 1200, distance: 1000)
        #expect(swim.paceOrSpeed == "2:00")
        #expect(swim.paceLabel.contains("100 m"))
        #expect(share(discipline: .cycling, duration: 3600, distance: 25000).paceOrSpeed == "25.0")
    }

    @Test("Invalid measurements are absent, never zero or NaN")
    func invalidEvidence() {
        let snapshot = share(discipline: .running, duration: .nan, distance: .infinity)
        #expect(snapshot.durationText == nil)
        #expect(snapshot.distanceText == nil)
        #expect(snapshot.paceOrSpeed == nil)
    }

    @Test("A wide route keeps its proportions in a tall story canvas")
    func aspectRatio() throws {
        let route = WorkoutShareRoute(points: [point(0, 0), point(0.01, 0.1, second: 1)])
        let fitted = try #require(route.fittedSegments(in: CGSize(width: 400, height: 800)).first)
        let first = try #require(fitted.first)
        let last = try #require(fitted.last)
        let ratio = abs((last.x - first.x) / (last.y - first.y))
        #expect(abs(ratio - 10) < 0.01)
        #expect(first.x >= 30 && last.x <= 370)
    }

    @Test("International date line crossings stay local")
    func dateLine() {
        let route = WorkoutShareRoute(points: [point(10, 179.999), point(10.001, -179.999, second: 1)])
        #expect(route.hasRoute)
        #expect(route.bounds.size.width < MKMapRect.world.size.width / 1000)
    }

    @Test("Missing GPS fixes and pauses do not draw invented connections")
    func gaps() {
        let route = WorkoutShareRoute(points: [
            point(10, 10), point(10.001, 10.001, second: 1), point(.nan, 10, second: 2),
            point(11, 11, second: 3), point(11.001, 11.001, second: 4),
            point(12, 12, second: 200), point(12.001, 12.001, second: 201)
        ])
        #expect(route.segments.count == 3)
        #expect(route.segments.allSatisfy { $0.count == 2 })
    }

    @Test("Empty, single-fix and stationary traces are not shareable routes")
    func noRoute() {
        #expect(!WorkoutShareRoute(points: []).hasRoute)
        #expect(!WorkoutShareRoute(points: [point(10, 10)]).hasRoute)
        #expect(!WorkoutShareRoute(points: [point(10, 10), point(10, 10, second: 1)]).hasRoute)
    }

    @Test("Route access uses the selected provider and respects its authorization")
    func providerRoute() async throws {
        var provider = StubHealthDataProvider()
        provider.storedRoute = [point(10, 10), point(10.001, 10.001, second: 1)]
        let loaded = try await provider.route(forWorkout: UUID())
        #expect(loaded == provider.storedRoute)
        provider.status = .denied
        do {
            _ = try await provider.route(forWorkout: UUID())
            Issue.record("A denied provider returned GPS data")
        } catch {
            #expect(error as? HealthDataError == .notAuthorized)
        }
    }

    private func point(_ latitude: Double, _ longitude: Double, second: Double = 0) -> RecordedRoutePoint {
        RecordedRoutePoint(latitude: latitude, longitude: longitude,
                           timestamp: Date(timeIntervalSince1970: second))
    }

    private func share(discipline: Discipline, duration: Double, distance: Double) -> WorkoutShareSnapshot {
        let workout = PlannedWorkout(date: .now, discipline: discipline, title: "Workout", status: .completed)
        workout.importedSummary = ImportedWorkoutSummary(
            healthKitUUID: UUID(), sport: discipline.sport!, startDate: .now, endDate: .now,
            duration: duration, distanceMeters: distance
        )
        return WorkoutShareSnapshot(workout: workout)
    }
}
