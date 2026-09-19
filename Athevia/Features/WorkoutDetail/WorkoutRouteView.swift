import CoreLocation
import MapKit
import SwiftUI

/// Read-only route evidence captured by the iPhone workout player.
struct WorkoutRouteView: View {
    let points: [RecordedRoutePoint]

    private var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        if coordinates.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(text: "Route")

                Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.tint, lineWidth: 4)

                    if let first = coordinates.first {
                        Marker("Start", systemImage: "play.fill", coordinate: first)
                            .tint(.green)
                    }
                    if let last = coordinates.last {
                        Marker("Finish", systemImage: "flag.checkered", coordinate: last)
                    }
                }
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 16))
            }
        }
    }
}