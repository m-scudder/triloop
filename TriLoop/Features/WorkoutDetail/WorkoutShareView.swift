import ImageIO
import PhotosUI
import SwiftUI
import UIKit

private enum WorkoutShareFormat: String, CaseIterable, Identifiable {
    case story, square
    var id: String { rawValue }
    var title: String { self == .story ? "Story" : "Post" }
    var exportSize: CGSize {
        self == .story ? CGSize(width: 1080, height: 1920) : CGSize(width: 1080, height: 1080)
    }
    var routeSize: CGSize {
        self == .story ? CGSize(width: 920, height: 680) : CGSize(width: 952, height: 430)
    }
}

private enum WorkoutShareBackground: String, CaseIterable, Identifiable {
    case map, photo, dark, transparent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .map: "Map"
        case .photo: "Photo"
        case .dark: "Dark"
        case .transparent: "Transparent"
        }
    }
}

private struct WorkoutShareCard: View {
    let snapshot: WorkoutShareSnapshot
    let format: WorkoutShareFormat
    let background: WorkoutShareBackground
    let route: WorkoutShareRoute
    let showsRoute: Bool
    let mapImage: UIImage?
    let photo: UIImage?

    private var isStory: Bool { format == .story }

    var body: some View {
        ZStack {
            if background != .transparent { Color.black }
            if background == .photo, let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: format.exportSize.width, height: format.exportSize.height)
                    .clipped()
                LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.15), .black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
            }
            VStack(alignment: .leading, spacing: isStory ? 38 : 26) {
                VStack(alignment: .leading, spacing: isStory ? 28 : 18) {
                    Text("TriLoop")
                        .font(.system(size: isStory ? 40 : 32, weight: .bold, design: .rounded))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(snapshot.title)
                            .font(.system(size: isStory ? 58 : 46, weight: .bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                        Text(snapshot.date.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                Spacer(minLength: 0)
                if showsRoute, route.hasRoute {
                    if background == .map, let mapImage {
                        Image(uiImage: mapImage)
                            .resizable()
                            .frame(width: format.routeSize.width, height: format.routeSize.height)
                            .clipShape(.rect(cornerRadius: 24))
                    } else {
                        WorkoutShareRouteShape(route: route, color: background == .photo ? .white : .orange)
                            .frame(height: format.routeSize.height)
                    }
                }
                Spacer(minLength: 0)
                if isStory {
                    VStack(alignment: .leading, spacing: 28) { metrics }
                } else {
                    HStack(alignment: .top, spacing: 26) { metrics }
                }
            }
            .padding(.horizontal, isStory ? 80 : 64)
            .padding(.top, isStory ? 140 : 64)
            .padding(.bottom, isStory ? 160 : 64)
        }
        .foregroundStyle(.white)
        .frame(width: format.exportSize.width, height: format.exportSize.height)
        .clipped()
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    @ViewBuilder
    private var metrics: some View {
        if let distance = snapshot.distanceText { metric(distance, label: "Distance · km") }
        if let duration = snapshot.durationText { metric(duration, label: "Time") }
        if let pace = snapshot.paceOrSpeed { metric(pace, label: snapshot.paceLabel) }
        if snapshot.distanceText == nil, snapshot.durationText == nil, snapshot.paceOrSpeed == nil {
            Text("Workout completed")
                .font(.system(size: 42, weight: .semibold))
        }
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: isStory ? 76 : 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: isStory ? 28 : 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkoutShareView: View {
    let workout: PlannedWorkout
    @Environment(\.dismiss) private var dismiss
    @Environment(\.healthProvider) private var health
    @State private var format: WorkoutShareFormat = .story
    @State private var background: WorkoutShareBackground = .map
    @State private var showsRoute = true
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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isLoadingPhoto = false
    @State private var exportedFile: WorkoutShareFile?
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var lastExportURL: URL?

    private var snapshot: WorkoutShareSnapshot { WorkoutShareSnapshot(workout: workout) }
    private var route: WorkoutShareRoute {
        WorkoutShareRoute(points: loadedRoute.isEmpty ? snapshot.route : loadedRoute)
    }
    private var mapRequest: String {
        "\(format.rawValue)-\(background.rawValue)-\(showsRoute)-\(routeRevision)-\(mapRetry)"
    }
    private var canShare: Bool {
        !isExporting && !isLoadingPhoto && !(showsRoute && isLoadingRoute)
            && (!(background == .map && showsRoute && route.hasRoute)
                || (preparedMapRequest == mapRequest && !isLoadingMap))
            && (background != .photo || photo != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    preview
                        .frame(maxWidth: previewMaxWidth)
                        .frame(maxWidth: .infinity)
                    Picker("Format", selection: $format) {
                        ForEach(WorkoutShareFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Background", selection: $background) {
                        ForEach(WorkoutShareBackground.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if background == .photo {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(photo == nil ? "Choose photo" : "Change photo", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    if background == .transparent {
                        Text("PNG with a transparent background, ready to layer over your own photo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    routeControls
                    if mapFailed, background == .map, showsRoute, route.hasRoute {
                        HStack {
                            Text("Map unavailable. Your route will still be shared.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") { mapRetry += 1 }
                        }
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: exportCard) {
                    Label("Share workout", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!canShare)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("Share workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: routeRequest) { await loadRoute() }
            .task(id: mapRequest) { await loadMap() }
            .task(id: selectedPhoto) { await loadPhoto() }
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
    }

    private var card: some View {
        WorkoutShareCard(snapshot: snapshot, format: format, background: background,
                         route: route, showsRoute: showsRoute,
                         mapImage: preparedMapRequest == mapRequest ? mapImage : nil, photo: photo)
    }

    private var preview: some View {
        GeometryReader { geometry in
            card
                .scaleEffect(geometry.size.width / format.exportSize.width, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .aspectRatio(format.exportSize.width / format.exportSize.height, contentMode: .fit)
        .background {
            if background == .transparent { CheckerboardBackground() }
        }
        .clipShape(.rect(cornerRadius: 18))
        .overlay(alignment: .center) {
            if isLoadingRoute || isLoadingMap || isLoadingPhoto {
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
        parts.append(showsRoute && route.hasRoute ? "route included" : "no route")
        return parts.joined(separator: ", ")
    }

    private var previewMaxWidth: CGFloat {
        let size = format.exportSize
        return 280 * size.width / size.height
    }

    @ViewBuilder
    private var routeControls: some View {
        if route.hasRoute {
            Toggle("Include GPS route", isOn: $showsRoute)
        } else if isLoadingRoute {
            HStack {
                Text("Loading GPS route…").foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            HStack(alignment: .top) {
                Text(routeMessage ?? "No GPS route recorded for this workout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let summary = workout.importedSummary, summary.source != "TriLoop iPhone" {
                    Button("Retry") { routeRequest += 1 }
                }
            }
        }
    }

    @MainActor
    private func loadRoute() async {
        isLoadingRoute = true
        routeMessage = nil
        defer { isLoadingRoute = false }
        guard !WorkoutShareRoute(points: snapshot.route).hasRoute,
              let summary = workout.importedSummary,
              summary.source != "TriLoop iPhone" else { return }
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
        guard background == .map, showsRoute, route.hasRoute else { return }
        isLoadingMap = true
        do {
            let image = try await WorkoutShareMap.image(route: route, size: format.routeSize)
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
    private func loadPhoto() async {
        isLoadingPhoto = false
        guard let selectedPhoto else { return }
        isLoadingPhoto = true
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2560
                  ] as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try Task.checkCancellation()
            // Downsample before decoding a full-resolution camera image.
            photo = UIImage(cgImage: thumbnail)
        } catch {
            guard !Task.isCancelled else { return }
            exportError = "Couldn't open this photo. Please choose another image."
        }
        isLoadingPhoto = false
    }

    @MainActor
    private func exportCard() {
        guard canShare else { return }
        isExporting = true
        defer { isExporting = false }
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(format.exportSize)
        renderer.scale = 1
        renderer.isOpaque = background != .transparent
        guard let data = renderer.uiImage?.pngData() else {
            exportError = "Couldn't create the image. Please try again."
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("TriLoop-\(UUID().uuidString).png")
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
