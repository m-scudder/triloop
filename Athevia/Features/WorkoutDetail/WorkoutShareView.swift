import Photos
import SwiftUI
import UIKit

private enum WorkoutShareStyle: String, CaseIterable, Identifiable {
    case card
    case transparent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: "Card"
        case .transparent: "Transparent"
        }
    }

    static let exportSize = CGSize(width: 1080, height: 1350)
    static let routeSize = CGSize(width: 952, height: 620)
}

private struct WorkoutShareCard: View {
    let snapshot: WorkoutShareSnapshot
    let style: WorkoutShareStyle
    let route: WorkoutShareRoute
    let mapImage: UIImage?

    private var hasRoute: Bool { route.hasRoute }

    var body: some View {
        ZStack {
            if style == .card {
                Color.black
            }

            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Athevia")
                            .font(.system(size: 34, weight: .bold, design: .rounded))

                        Text(snapshot.title)
                            .font(.system(size: 54, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text(TrainingFormatter.shortDate(snapshot.date, includeYear: true))
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer()

                    Image(systemName: snapshot.discipline.symbolName)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                if hasRoute {
                    Group {
                        if style == .card, let mapImage {
                            Image(uiImage: mapImage)
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: WorkoutShareStyle.routeSize.width,
                                    height: WorkoutShareStyle.routeSize.height
                                )
                                .clipped()
                                .clipShape(.rect(cornerRadius: 24))
                        } else {
                            WorkoutShareRouteShape(route: route, color: .orange)
                                .frame(height: WorkoutShareStyle.routeSize.height)
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                HStack(alignment: .top, spacing: 26) {
                    metrics
                }
            }
            .padding(.horizontal, 64)
            .padding(.top, 70)
            .padding(.bottom, 72)
        }
        .foregroundStyle(.white)
        .frame(
            width: WorkoutShareStyle.exportSize.width,
            height: WorkoutShareStyle.exportSize.height
        )
        .clipped()
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    @ViewBuilder
    private var metrics: some View {
        if let distance = snapshot.distanceText {
            metric(distance, label: snapshot.distanceLabel)
        }

        if let duration = snapshot.durationText {
            metric(duration, label: "Time")
        }

        if let pace = snapshot.paceOrSpeed {
            metric(pace, label: snapshot.paceLabel)
        }

        if snapshot.distanceText == nil,
           snapshot.durationText == nil,
           snapshot.paceOrSpeed == nil {
            Text("Workout completed")
                .font(.system(size: 42, weight: .semibold))
        }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkoutShareView: View {
    let workout: PlannedWorkout
    var titleOverride: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.healthProvider) private var health
    @State private var style: WorkoutShareStyle = .card
    @State private var loadedRoute: [RecordedRoutePoint] = []
    @State private var routeRevision = 0
    @State private var routeRequest = 0
    @State private var isLoadingRoute = true
    @State private var routeMessage: String?
    @State private var mapImage: UIImage?
    @State private var preparedMapRequest = ""
    @State private var isLoadingMap = false
    @State private var mapFailed = false
    @State private var mapRetry = 0
    @State private var exportedFile: WorkoutShareFile?
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var isSavingToPhotos = false
    @State private var saveMessage: String?
    @State private var lastExportURL: URL?

    private var snapshot: WorkoutShareSnapshot {
        WorkoutShareSnapshot(workout: workout, titleOverride: titleOverride)
    }
    private var route: WorkoutShareRoute {
        WorkoutShareRoute(points: loadedRoute.isEmpty ? snapshot.route : loadedRoute)
    }
    private var mapRequest: String {
        "\(style.rawValue)-\(routeRevision)-\(mapRetry)"
    }

    private var canShare: Bool {
        !isExporting
            && !isLoadingRoute
            && (style != .card || !route.hasRoute || (preparedMapRequest == mapRequest && !isLoadingMap))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    preview
                        .frame(maxWidth: previewMaxWidth)
                        .frame(maxWidth: .infinity)
                    Picker("Style", selection: $style) {
                        ForEach(WorkoutShareStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    if style == .transparent {
                        Text("Transparent PNG for layering over Reels or your own media.")
                            .font(.caption)
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if isLoadingRoute {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Checking for GPS route…")
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !route.hasRoute, let routeMessage {
                        Text(routeMessage)
                            .font(.caption)
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if mapFailed, style == .card, route.hasRoute {
                        HStack {
                            Text("Map unavailable. Your route will still be shared.")
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                            Spacer()
                            Button("Retry") { mapRetry += 1 }
                        }
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Button(action: saveToPhotos) {
                            Label(
                                isSavingToPhotos ? "Saving…" : "Save to Photos",
                                systemImage: "square.and.arrow.down"
                            )
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(!canShare || isSavingToPhotos)

                        Button(action: exportCard) {
                            Label("Share workout", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(!canShare || isSavingToPhotos)
                    }

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(AtheviaAdaptiveStyle(.bar, gaming: .surface))
            }
            .atheviaScreen()
            .navigationTitle("Share workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: routeRequest) { await loadRoute() }
            .task(id: mapRequest) { await loadMap() }
            .sheet(item: $exportedFile, onDismiss: removeExport) { file in
                WorkoutActivityView(file: file.url)
                    .presentationDetents([.medium, .large])
            }
            .alert("Couldn't prepare your share", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "Please try again.")
            }
        }
        .atheviaScreen()
    }

    private var card: some View {
        WorkoutShareCard(
            snapshot: snapshot,
            style: style,
            route: route,
            mapImage: preparedMapRequest == mapRequest ? mapImage : nil
        )
    }

    private var preview: some View {
        GeometryReader { geometry in
            card
                .scaleEffect(geometry.size.width / WorkoutShareStyle.exportSize.width, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .aspectRatio(WorkoutShareStyle.exportSize.width / WorkoutShareStyle.exportSize.height, contentMode: .fit)
        .background {
            if style == .transparent { CheckerboardBackground() }
        }
        .clipShape(.rect(cornerRadius: 18))
        .overlay(alignment: .center) {
            if isLoadingRoute || isLoadingMap {
                ProgressView().tint(.white).padding(12).background(.black.opacity(0.65), in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout sharing preview")
        .accessibilityValue(previewAccessibilityValue)
    }

    private var previewAccessibilityValue: String {
        var parts: [String] = [snapshot.title]
        if let distance = snapshot.distanceText {
            parts.append("\(distance) kilometres")
        }
        if let duration = snapshot.durationText {
            parts.append(duration)
        }
        parts.append(route.hasRoute ? "route included" : "no route")
        return parts.joined(separator: ", ")
    }

    private var previewMaxWidth: CGFloat {
        let size = WorkoutShareStyle.exportSize
        return 320 * size.width / size.height
    }

    @MainActor
    private func loadRoute() async {
        isLoadingRoute = true
        routeMessage = nil
        defer { isLoadingRoute = false }
        guard !WorkoutShareRoute(points: snapshot.route).hasRoute,
              let summary = workout.importedSummary,
              !["Athevia iPhone", "Athevia iPhone"].contains(summary.source) else { return }
        do {
            try await health.requestAuthorization()
            let points = try await health.route(forWorkout: summary.healthKitUUID)
            try Task.checkCancellation()
            loadedRoute = points
            routeRevision += 1
            if !WorkoutShareRoute(points: points).hasRoute {
                routeMessage = "No GPS route available. Check Workout Routes access in Apple Health, or retry after your watch syncs."
            }
        } catch is CancellationError {
            return
        } catch {
            routeMessage = "Couldn't load the GPS route. You can still share your stats."
        }
    }

    @MainActor
    private func loadMap() async {
        let request = mapRequest
        mapImage = nil
        mapFailed = false
        isLoadingMap = false
        guard style == .card, route.hasRoute else { return }
        isLoadingMap = true
        do {
            let image = try await WorkoutShareMap.image(route: route, size: WorkoutShareStyle.routeSize)
            try Task.checkCancellation()
            guard request == mapRequest else { return }
            mapImage = image
        } catch {
            guard !Task.isCancelled, request == mapRequest else { return }
            mapFailed = true
        }
        preparedMapRequest = request
        isLoadingMap = false
    }

    @MainActor
    private func renderedPNGData() -> Data? {
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(WorkoutShareStyle.exportSize)
        renderer.scale = 1
        renderer.isOpaque = style != .transparent
        return renderer.uiImage?.pngData()
    }

    @MainActor
    private func saveToPhotos() {
        guard canShare, !isSavingToPhotos else { return }
        guard let data = renderedPNGData() else {
            exportError = "Couldn't create the image. Please try again."
            return
        }

        isSavingToPhotos = true
        saveMessage = nil

        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                await MainActor.run {
                    isSavingToPhotos = false
                    exportError = "Allow Photos access in Settings to save workout images."
                }
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = "Athevia-Workout.png"
                    request.addResource(with: .photo, data: data, options: options)
                }
                await MainActor.run {
                    isSavingToPhotos = false
                    saveMessage = "Saved to Photos."
                }
            } catch {
                await MainActor.run {
                    isSavingToPhotos = false
                    exportError = "Couldn't save this workout to Photos. Please try again."
                }
            }
        }
    }

    @MainActor
    private func exportCard() {
        guard canShare else { return }
        isExporting = true
        defer { isExporting = false }
        guard let data = renderedPNGData() else {
            exportError = "Couldn't create the image. Please try again."
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Athevia-\(UUID().uuidString).png")
            try data.write(to: url, options: .atomic)
            lastExportURL = url
            exportedFile = WorkoutShareFile(url: url)
        } catch {
            exportError = "Couldn't save the image for sharing. Please try again."
        }
    }

    private func removeExport() {
        if let lastExportURL { try? FileManager.default.removeItem(at: lastExportURL) }
        lastExportURL = nil
    }
}

private struct WorkoutShareFile: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 16
            for row in 0..<Int(ceil(size.height / cell)) {
                for column in 0..<Int(ceil(size.width / cell)) {
                    let shade = (row + column).isMultiple(of: 2) ? Color(white: 0.20) : Color(white: 0.28)
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                             width: cell, height: cell)), with: .color(shade))
                }
            }
        }
    }
}

private struct WorkoutActivityView: UIViewControllerRepresentable {
    let file: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // A PNG file keeps transparency; handing UIKit a UIImage can become JPEG.
        UIActivityViewController(activityItems: [file], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

