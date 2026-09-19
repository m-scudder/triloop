import MapKit
import SwiftUI
import UIKit

/// Project GPS into map space once and fit with a single scale on both axes.
/// Invalid fixes and long recording gaps break the line instead of inventing a leg.
struct WorkoutShareRoute {
    let segments: [[MKMapPoint]]

    init(points: [RecordedRoutePoint]) {
        var result: [[MKMapPoint]] = []
        var segment: [MKMapPoint] = []
        var previous: RecordedRoutePoint?
        var previousX: Double?
        let worldWidth = MKMapRect.world.size.width
        for point in points {
            let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            guard point.latitude.isFinite, point.longitude.isFinite,
                  CLLocationCoordinate2DIsValid(coordinate), abs(point.latitude) < 85.051_129 else {
                if segment.count >= 2 { result.append(segment) }
                segment = []
                previous = nil
                continue
            }
            if let previous, point.timestamp.timeIntervalSince(previous.timestamp) > 90 {
                if segment.count >= 2 { result.append(segment) }
                segment = []
            }
            var projected = MKMapPoint(coordinate)
            // Keep routes crossing ±180° together instead of spanning the world.
            if let previousX {
                while projected.x - previousX > worldWidth / 2 { projected.x -= worldWidth }
                while projected.x - previousX < -worldWidth / 2 { projected.x += worldWidth }
            }
            segment.append(projected)
            previous = point
            previousX = projected.x
        }
        if segment.count >= 2 { result.append(segment) }
        segments = result
    }

    var hasRoute: Bool {
        segments.contains { segment in
            guard let first = segment.first else { return false }
            return segment.contains { $0.x != first.x || $0.y != first.y }
        }
    }

    var bounds: MKMapRect {
        let points = segments.flatMap { $0 }
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return MKMapRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    func fittedSegments(in size: CGSize, inset: CGFloat = 30) -> [[CGPoint]] {
        guard hasRoute else { return [] }
        let rect = bounds
        let scale = min(max(size.width - inset * 2, 1) / rect.size.width,
                        max(size.height - inset * 2, 1) / rect.size.height)
        let origin = CGPoint(x: (size.width - rect.size.width * scale) / 2,
                             y: (size.height - rect.size.height * scale) / 2)
        return segments.map { segment in
            segment.map { CGPoint(x: origin.x + ($0.x - rect.origin.x) * scale,
                                  y: origin.y + ($0.y - rect.origin.y) * scale) }
        }
    }
}

struct WorkoutShareRouteShape: View {
    let route: WorkoutShareRoute
    var color: Color = .orange

    var body: some View {
        Canvas { context, size in
            for segment in route.fittedSegments(in: size) {
                guard let first = segment.first else { continue }
                var path = Path()
                path.move(to: first)
                for point in segment.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(.black.opacity(0.25)),
                               style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

enum WorkoutShareMap {
    /// Snapshotting avoids blank Map views in SwiftUI ImageRenderer exports.
    @MainActor
    static func image(route: WorkoutShareRoute, size: CGSize) async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        let bounds = route.bounds
        let padding = max(bounds.size.width, bounds.size.height) * 0.15 + 150
        options.mapRect = bounds.insetBy(dx: -padding, dy: -padding)
        options.size = size
        options.scale = 1
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot = try await withTaskCancellationHandler {
            try await snapshotter.start()
        } onCancel: {
            snapshotter.cancel()
        }
        try Task.checkCancellation()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            // Preserve the complete map snapshot, including Apple's attribution.
            snapshot.image.draw(at: .zero)
            for segment in route.segments {
                let path = UIBezierPath()
                for (index, point) in segment.enumerated() {
                    let location = snapshot.point(for: point.coordinate)
                    if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.lineWidth = 15
                UIColor.black.withAlphaComponent(0.5).setStroke()
                path.stroke()
                path.lineWidth = 9
                UIColor.systemOrange.setStroke()
                path.stroke()
            }
        }
    }
}
