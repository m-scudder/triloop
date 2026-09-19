import SwiftUI
import UIKit

/// A stable, share-focused projection of a completed workout.
struct WorkoutShareSnapshot {
    let title: String
    let sport: String
    let date: Date
    let duration: TimeInterval?
    let distanceMeters: Double?
    let speedMetersPerSecond: Double?
    let route: [RecordedRoutePoint]

    @MainActor
    init(workout: PlannedWorkout) {
        let summary = workout.importedSummary
        title = workout.title
        sport = workout.discipline.displayName
        date = summary?.startDate ?? workout.completedAt ?? workout.date
        duration = summary?.duration ?? workout.prescribedDurationSeconds
        distanceMeters = summary?.distanceMeters
        speedMetersPerSecond = workout.discipline == .cycling
            ? summary?.metrics?.averageCyclingSpeed
            : summary?.metrics?.averageRunningSpeed
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

private enum WorkoutShareFormat: String, CaseIterable, Identifiable {
    case story
    case square

    var id: String { rawValue }
    var title: String { self == .story ? "Story" : "Post" }
    var icon: String { self == .story ? "rectangle.portrait" : "square" }
    var exportSize: CGSize { self == .story ? CGSize(width: 1080, height: 1920) : CGSize(width: 1080, height: 1080) }
}

private enum WorkoutShareBackground: String, CaseIterable, Identifiable {
    case black
    case transparent

    var id: String { rawValue }
    var title: String { self == .black ? "Black" : "Transparent" }
}

struct WorkoutShareCard: View {
    let snapshot: WorkoutShareSnapshot
    fileprivate let format: WorkoutShareFormat
    fileprivate let background: WorkoutShareBackground
    let showsRoute: Bool

    private var isStory: Bool { format == .story }

    var body: some View {
        ZStack {
            if background == .black {
                Color.black
            }

            if isStory {
                storyContent
            } else {
                squareContent
            }
        }
        .foregroundStyle(.white)
    }

    private var storyContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            titleBlock
                .padding(.top, 54)

            VStack(alignment: .leading, spacing: 46) {
                metricRow(icon: "ruler", value: distanceText, label: "Distance")
                metricRow(icon: "clock", value: durationText, label: "Duration")
                metricRow(icon: "speedometer", value: snapshot.paceOrSpeed ?? "—", label: paceLabel)
            }
            .padding(.top, 72)

            Spacer(minLength: 40)

            if showsRoute, snapshot.route.count >= 2 {
                route
                    .frame(height: 560)
                    .padding(.bottom, 54)
            }

            Text("Train · Progress · Repeat")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.60))
        }
        .padding(72)
    }

    private var squareContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            titleBlock
                .padding(.top, 36)

            if showsRoute, snapshot.route.count >= 2 {
                HStack(alignment: .center, spacing: 50) {
                    VStack(alignment: .leading, spacing: 34) {
                        metricRow(icon: "ruler", value: distanceText, label: "Distance")
                        metricRow(icon: "clock", value: durationText, label: "Duration")
                        metricRow(icon: "speedometer", value: snapshot.paceOrSpeed ?? "—", label: paceLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    route
                        .frame(maxWidth: .infinity)
                        .frame(height: 470)
                }
                .padding(.top, 48)
            } else {
                HStack(alignment: .top, spacing: 36) {
                    compactMetric("ruler", distanceText, "Distance")
                    compactMetric("clock", durationText, "Duration")
                    compactMetric("speedometer", snapshot.paceOrSpeed ?? "—", paceLabel)
                }
                .padding(.top, 70)

                Spacer()
            }

            Spacer(minLength: 28)
            Text("Train · Progress · Repeat")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.60))
        }
        .padding(64)
    }

    private var brand: some View {
        Label("TriLoop", systemImage: "point.3.connected.trianglepath.dotted")
            .font(.system(size: isStory ? 34 : 30, weight: .bold))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snapshot.title)
                .font(.system(size: isStory ? 62 : 52, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(snapshot.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                .font(.system(size: isStory ? 28 : 25))
                .foregroundStyle(.white.opacity(0.70))
        }
    }

    private var route: some View {
        ShareRouteShape(points: snapshot.route)
            .padding(20)
    }

    private var distanceText: String {
        snapshot.distanceMeters.map { TrainingFormatter.distance(meters: $0) } ?? "—"
    }

    private var durationText: String {
        snapshot.duration.map { TrainingFormatter.totalDuration(seconds: $0) } ?? "—"
    }

    private var paceLabel: String {
        snapshot.sport.lowercased().contains("cycl") ? "Avg speed" : "Avg pace"
    }

    private func metricRow(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 28) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .medium))
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 48, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 27))
                    .foregroundStyle(.white.opacity(0.70))
            }
        }
    }

    private func compactMetric(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
            Text(value)
                .font(.system(size: 38, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 23))
                .foregroundStyle(.white.opacity(0.70))
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
            let inset: CGFloat = 18
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
            for routePoint in points.dropFirst() {
                path.addLine(to: point(routePoint))
            }

            // High-contrast route colour deliberately separated from TriLoop's
            // monochrome card so a real GPS trace remains visually dominant.
            context.stroke(
                path,
                with: .color(Color(red: 1.0, green: 0.36, blue: 0.05)),
                style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }
}

struct WorkoutShareView: View {
    let workout: PlannedWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var format: WorkoutShareFormat = .story
    @State private var shareBackground: WorkoutShareBackground = .black
    @State private var showsRoute = false
    @State private var shareImage: UIImage?

    private var snapshot: WorkoutShareSnapshot { WorkoutShareSnapshot(workout: workout) }
    private var hasRoute: Bool { snapshot.route.count >= 2 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    WorkoutShareCard(
                        snapshot: snapshot,
                        format: format,
                        background: shareBackground,
                        showsRoute: showsRoute
                    )
                    .aspectRatio(format.exportSize.width / format.exportSize.height, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(previewBackground)
                    .clipShape(.rect(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)

                    Picker("Format", selection: $format) {
                        ForEach(WorkoutShareFormat.allCases) { option in
                            Label(option.title, systemImage: option.icon).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Background", selection: $shareBackground) {
                        ForEach(WorkoutShareBackground.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if shareBackground == .transparent {
                        Text("Transparent PNG can be placed over your own photo or Story background.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

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

    @ViewBuilder
    private var previewBackground: some View {
        if shareBackground == .transparent {
            CheckerboardBackground()
        } else {
            Color.black
        }
    }

    @MainActor
    private func renderCard() -> UIImage? {
        let size = format.exportSize
        let renderer = ImageRenderer(
            content: WorkoutShareCard(
                snapshot: snapshot,
                format: format,
                background: shareBackground,
                showsRoute: showsRoute
            )
            .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        renderer.isOpaque = shareBackground == .black
        return renderer.uiImage
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 16
            let rows = Int(ceil(size.height / cell))
            let columns = Int(ceil(size.width / cell))
            for row in 0..<rows {
                for column in 0..<columns {
                    let shade = (row + column).isMultiple(of: 2)
                        ? Color(uiColor: .systemGray5)
                        : Color(uiColor: .systemGray4)
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                        with: .color(shade)
                    )
                }
            }
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
