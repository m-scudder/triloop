import SwiftUI
import UIKit

/// A stable, share-focused projection of a completed workout.
struct WorkoutShareSnapshot {
    let title: String
    let sport: String
    let symbol: String
    let date: Date
    let duration: TimeInterval?
    let distanceMeters: Double?
    let averageHeartRate: Double?
    let elevationMeters: Double?
    let cadence: Double?
    let speedMetersPerSecond: Double?
    let actualRPE: Int?
    let route: [RecordedRoutePoint]

    @MainActor
    init(workout: PlannedWorkout) {
        let summary = workout.importedSummary
        title = workout.title
        sport = workout.discipline.displayName
        symbol = workout.discipline.symbolName
        date = summary?.startDate ?? workout.completedAt ?? workout.date
        duration = summary?.duration ?? workout.prescribedDurationSeconds
        distanceMeters = summary?.distanceMeters
        averageHeartRate = summary?.averageHeartRate
        elevationMeters = summary?.elevationAscendedMeters
        cadence = summary?.metrics?.averageCadence ?? summary?.metrics?.averageCyclingCadence
        speedMetersPerSecond = workout.discipline == .cycling
            ? summary?.metrics?.averageCyclingSpeed
            : summary?.metrics?.averageRunningSpeed
        actualRPE = workout.feedback?.rpe
        route = summary?.metrics?.route ?? []
    }

    var paceOrSpeed: String? {
        let derivedSpeed: Double? = {
            guard let distanceMeters, let duration, duration > 0 else { return nil }
            return distanceMeters / duration
        }()
        guard let speed = speedMetersPerSecond ?? derivedSpeed, speed > 0 else { return nil }

        if sport.lowercased().contains("cycl") {
            return String(format: "%.1f km/h", speed * 3.6)
        }
        let seconds = Int((1_000 / speed).rounded())
        guard seconds > 0, seconds < 3_600 else { return nil }
        return String(format: "%d:%02d /km", seconds / 60, seconds % 60)
    }
}

struct WorkoutShareCard: View {
    let snapshot: WorkoutShareSnapshot
    let showsRoute: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Label("TriLoop", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text(snapshot.sport)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.title)
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(2)
                Text(snapshot.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                if let distance = snapshot.distanceMeters {
                    shareStat(TrainingFormatter.distance(meters: distance), "Distance")
                }
                if let duration = snapshot.duration {
                    shareStat(TrainingFormatter.totalDuration(seconds: duration), "Duration")
                }
                if let pace = snapshot.paceOrSpeed {
                    shareStat(pace, snapshot.sport.lowercased().contains("cycl") ? "Avg speed" : "Avg pace")
                }
            }

            if showsRoute, snapshot.route.count >= 2 {
                ShareRouteShape(points: snapshot.route)
                    .frame(height: 210)
                    .padding(14)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 18))
            }


            HStack {
                Text("Train · Progress · Repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("TriLoop")
                    .font(.headline.weight(.bold))
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.20),
                    Color(uiColor: .secondarySystemBackground),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func shareStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShareRouteShape: View {
    let points: [RecordedRoutePoint]

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            let lats = points.map(\.latitude)
            let longs = points.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLong = longs.min(), let maxLong = longs.max() else { return }

            let latSpan = max(maxLat - minLat, 0.000_001)
            let longSpan = max(maxLong - minLong, 0.000_001)
            let inset: CGFloat = 10
            let width = max(size.width - inset * 2, 1)
            let height = max(size.height - inset * 2, 1)

            func point(_ routePoint: RecordedRoutePoint) -> CGPoint {
                CGPoint(
                    x: inset + CGFloat((routePoint.longitude - minLong) / longSpan) * width,
                    y: inset + CGFloat((maxLat - routePoint.latitude) / latSpan) * height
                )
            }

            var path = Path()
            path.move(to: point(points[0]))
            for routePoint in points.dropFirst() { path.addLine(to: point(routePoint)) }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

struct WorkoutShareView: View {
    let workout: PlannedWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var showsRoute = false
    @State private var shareImage: UIImage?

    private var snapshot: WorkoutShareSnapshot { WorkoutShareSnapshot(workout: workout) }
    private var hasRoute: Bool { snapshot.route.count >= 2 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    WorkoutShareCard(snapshot: snapshot, showsRoute: showsRoute)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                    if hasRoute {
                        Toggle(isOn: $showsRoute) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show route")
                                Text("Route sharing is off by default for privacy.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        shareImage = renderCard()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
                .padding(20)
            }
            .navigationTitle("Share Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(
                get: { shareImage != nil },
                set: { if !$0 { shareImage = nil } }
            )) {
                if let shareImage {
                    ActivityView(items: [shareImage])
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    @MainActor
    private func renderCard() -> UIImage? {
        let renderer = ImageRenderer(content: WorkoutShareCard(snapshot: snapshot, showsRoute: showsRoute))
        renderer.proposedSize = ProposedViewSize(width: 720, height: nil)
        renderer.scale = 2
        return renderer.uiImage
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
