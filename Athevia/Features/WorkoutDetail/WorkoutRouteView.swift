import CoreLocation
import MapKit
import SwiftUI

/// Read-only route evidence captured by Athevia or loaded from HealthKit.
struct WorkoutRouteView: View {
    let points: [RecordedRoutePoint]

    private var segments: [[CLLocationCoordinate2D]] {
        var result: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []

        func flush() {
            if current.count >= 2 {
                result.append(current)
            }
            current.removeAll(keepingCapacity: true)
        }

        for point in points {
            let coordinate = CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude
            )

            guard point.latitude.isFinite,
                  point.longitude.isFinite,
                  CLLocationCoordinate2DIsValid(coordinate) else {
                flush()
                continue
            }

            current.append(coordinate)
        }

        flush()
        return result
    }

    private var firstCoordinate: CLLocationCoordinate2D? {
        segments.first?.first
    }

    private var lastCoordinate: CLLocationCoordinate2D? {
        segments.last?.last
    }

    var body: some View {
        if !segments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Route")

                Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
                    ForEach(segments.indices, id: \.self) { index in
                        MapPolyline(coordinates: segments[index])
                            .stroke(.tint, lineWidth: 4)
                    }

                    if let firstCoordinate {
                        Marker(
                            "Start",
                            systemImage: "play.fill",
                            coordinate: firstCoordinate
                        )
                        .tint(.green)
                    }

                    if let lastCoordinate {
                        Marker(
                            "Finish",
                            systemImage: "flag.checkered",
                            coordinate: lastCoordinate
                        )
                    }
                }
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 16))
            }
        }
    }
}
