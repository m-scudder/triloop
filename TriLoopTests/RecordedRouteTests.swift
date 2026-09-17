import Foundation
import Testing
@testable import TriLoop

@Suite("Phone workout route persistence")
struct RecordedRouteTests {
    @Test("Route points survive RecordedMetrics encoding")
    func routeRoundTrip() throws {
        let point = RecordedRoutePoint(
            latitude: 17.385,
            longitude: 78.4867,
            altitudeMeters: 510,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let original = RecordedMetrics(averageRunningSpeed: 2.8, route: [point])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecordedMetrics.self, from: data)

        #expect(decoded == original)
    }

    @Test("Older metrics without a route still decode")
    func olderMetricsDecode() throws {
        let json = Data(#"{"averageRunningSpeed":2.8}"#.utf8)
        let decoded = try JSONDecoder().decode(RecordedMetrics.self, from: json)

        #expect(decoded.averageRunningSpeed == 2.8)
        #expect(decoded.route.isEmpty)
    }
}