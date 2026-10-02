import Photos
import SwiftUI
import UIKit

private enum WorkoutShareLayout: String, CaseIterable, Identifiable {
    case centered
    case side
    case compact

    var id: String { rawValue }
}

private enum WorkoutShareCanvas {
    static let exportSize = CGSize(width: 1080, height: 1920)
    static let routeLarge = CGSize(width: 820, height: 650)
    static let routeSide = CGSize(width: 470, height: 560)
}

private struct WorkoutShareSticker: View {
    let snapshot: WorkoutShareSnapshot
    let layout: WorkoutShareLayout
    let route: WorkoutShareRoute

    private var hasRoute: Bool { route.hasRoute }

    var body: some View {
        Group {
            switch layout {
            case .centered:
                centeredLayout
            case .side:
                sideLayout
            case .compact:
                compactLayout
            }
        }
        .foregroundStyle(.white)
        .frame(
            width: WorkoutShareCanvas.exportSize.width,
            height: WorkoutShareCanvas.exportSize.height
        )
        .clipped()
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
    }

    private var centeredLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: hasRoute ? 300 : 470)

            if hasRoute {
                WorkoutShareRouteShape(route: route, color: .orange)
                    .frame(
                        width: WorkoutShareCanvas.routeLarge.width,
                        height: WorkoutShareCanvas.routeLarge.height
                    )
                    .padding(.bottom, 70)
            }

            centeredMetrics

            Spacer(minLength: hasRoute ? 250 : 470)
        }
        .frame(maxWidth: .infinity)
    }

    private var sideLayout: some View {
        VStack {
            Spacer()

            HStack(alignment: .center, spacing: 72) {
                if hasRoute {
                    WorkoutShareRouteShape(route: route, color: .orange)
                        .frame(
                            width: WorkoutShareCanvas.routeSide.width,
                            height: WorkoutShareCanvas.routeSide.height
                        )
                } else {
                    sportMark
                        .frame(width: 290)
                }

                VStack(alignment: .leading, spacing: 34) {
                    brand

                    ForEach(snapshot.metrics) { item in
                        metric(
                            item,
                            alignment: .leading,
                            valueSize: 48
                        )
                    }
                }
                .frame(maxWidth: 380, alignment: .leading)
            }
            .padding(.horizontal, 80)

            Spacer()
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: hasRoute ? 360 : 520)

            HStack(alignment: .top, spacing: 52) {
                VStack(alignment: .leading, spacing: 18) {
                    brand

                    Text(snapshot.title)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .lineLimit(1)

                    Text(TrainingFormatter.shortDate(snapshot.date, includeYear: true))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .frame(width: 310, alignment: .leading)

                VStack(alignment: .leading, spacing: 30) {
                    ForEach(snapshot.metrics) { item in
                        metric(
                            item,
                            alignment: .leading,
                            valueSize: 46
                        )
                    }
                }
                .frame(width: 360, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if hasRoute {
                WorkoutShareRouteShape(route: route, color: .orange)
                    .frame(width: 720, height: 500)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
            } else {
                sportMark
                    .frame(maxWidth: .infinity)
                    .padding(.top, 54)
            }

            Spacer(minLength: hasRoute ? 260 : 440)
        }
    }

    private var centeredMetrics: some View {
        VStack(spacing: 34) {
            ForEach(snapshot.metrics) { item in
                metric(
                    item,
                    alignment: .center,
                    valueSize: 66
                )
            }

            sportMark
                .padding(.top, 14)

            brand
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var sportMark: some View {
        Image(systemName: snapshot.discipline.symbolName)
            .font(.system(size: 54, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.orange)
    }

    private var brand: some View {
        Text("ATHEVIA")
            .font(.system(size: 38, weight: .black, design: .rounded))
            .tracking(1.8)
    }

    private func metric(
        _ item: WorkoutShareMetric,
        alignment: HorizontalAlignment,
        valueSize: CGFloat
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(item.label.replacingOccurrences(of: " · ", with: " "))
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(displayValue(for: item))
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }

    private func displayValue(for item: WorkoutShareMetric) -> String {
        switch item.label {
        case "Distance · m":
            return "\(item.value) m"
        case "Distance · km":
            return "\(item.value) km"
        case "Avg pace · /100 m":
            return "\(item.value) /100m"
        case "Avg pace · /km":
            return "\(item.value) /km"
        case "Avg speed · km/h":
            return "\(item.value) km/h"
        default:
            return item.value
        }
    }
}

struct WorkoutShareView: View {
    let workout: PlannedWorkout
    var titleOverride: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.healthProvider) private var health

    @State private var layout: WorkoutShareLayout = .centered
    @State private var loadedRoute: [RecordedRoutePoint] = []
    @State private var isLoadingRoute = true
    @State private var exportedFile: WorkoutShareFile?
    @State private var exportError: String?
    @State private var isExporting = false
    @State private var isSavingToPhotos = false
    @State private var saveMessage: String?
    @State private var lastExportURL: URL?

    private var snapshot: WorkoutShareSnapshot {
        WorkoutShareSnapshot(
            workout: workout,
            titleOverride: titleOverride
        )
    }

    private var route: WorkoutShareRoute {
        WorkoutShareRoute(
            points: loadedRoute.isEmpty
                ? snapshot.route
                : loadedRoute
        )
    }

    private var canShare: Bool {
        !isExporting && !isLoadingRoute
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $layout) {
                    ForEach(WorkoutShareLayout.allCases) { candidate in
                        preview(for: candidate)
                            .tag(candidate)
                    }
                }
                .tabViewStyle(
                    .page(indexDisplayMode: .always)
                )
                .indexViewStyle(
                    .page(backgroundDisplayMode: .never)
                )
                .frame(maxHeight: .infinity)

                if isLoadingRoute {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Checking workout route…")
                            .font(.caption)
                            .foregroundStyle(
                                AtheviaAdaptiveStyle(
                                    .secondary,
                                    gaming: .secondaryText
                                )
                            )
                    }
                    .padding(.bottom, 8)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actions
            }
            .atheviaScreen()
            .navigationTitle("Share Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .task {
                await loadRoute()
            }
            .sheet(
                item: $exportedFile,
                onDismiss: removeExport
            ) { file in
                WorkoutActivityView(file: file.url)
                    .presentationDetents([.medium, .large])
            }
            .alert(
                "Couldn't prepare your share",
                isPresented: Binding(
                    get: { exportError != nil },
                    set: {
                        if !$0 {
                            exportError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    exportError = nil
                }
            } message: {
                Text(exportError ?? "Please try again.")
            }
        }
        .atheviaScreen()
    }

    private func sticker(
        for layout: WorkoutShareLayout
    ) -> some View {
        WorkoutShareSticker(
            snapshot: snapshot,
            layout: layout,
            route: route
        )
    }

    private func preview(
        for layout: WorkoutShareLayout
    ) -> some View {
        GeometryReader { geometry in
            let width = min(
                geometry.size.width - 44,
                320
            )
            let height = width
                * WorkoutShareCanvas.exportSize.height
                / WorkoutShareCanvas.exportSize.width

            sticker(for: layout)
                .scaleEffect(
                    width / WorkoutShareCanvas.exportSize.width,
                    anchor: .topLeading
                )
                .frame(
                    width: width,
                    height: height,
                    alignment: .topLeading
                )
                .background {
                    CheckerboardBackground()
                }
                .clipShape(.rect(cornerRadius: 16))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .center
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout sharing preview")
        .accessibilityValue(previewAccessibilityValue)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: saveToPhotos) {
                    Label(
                        isSavingToPhotos
                            ? "Saving…"
                            : "Save",
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(!canShare || isSavingToPhotos)

                Button(action: exportSticker) {
                    Label(
                        "Share",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!canShare || isSavingToPhotos)
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(
                        AtheviaAdaptiveStyle(
                            .secondary,
                            gaming: .secondaryText
                        )
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            AtheviaAdaptiveStyle(
                .bar,
                gaming: .surface
            )
        )
    }

    private var previewAccessibilityValue: String {
        var parts = [snapshot.title]
        parts.append(
            contentsOf: snapshot.metrics.map {
                "\($0.value) \($0.label)"
            }
        )
        parts.append(
            route.hasRoute
                ? "route included"
                : "no route"
        )
        return parts.joined(separator: ", ")
    }

    @MainActor
    private func loadRoute() async {
        isLoadingRoute = true
        defer {
            isLoadingRoute = false
        }

        guard !WorkoutShareRoute(
            points: snapshot.route
        ).hasRoute,
        let summary = workout.importedSummary,
        summary.source != "Athevia iPhone" else {
            return
        }

        do {
            try await health.requestAuthorization()
            let points = try await health.route(
                forWorkout: summary.healthKitUUID
            )
            try Task.checkCancellation()
            loadedRoute = points
        } catch is CancellationError {
            return
        } catch {
            // Route is optional. Stat-only sticker layouts remain complete
            // when HealthKit has no GPS evidence or route permission.
            loadedRoute = []
        }
    }

    @MainActor
    private func renderedPNGData() -> Data? {
        let renderer = ImageRenderer(
            content: sticker(for: layout)
        )
        renderer.proposedSize = ProposedViewSize(
            WorkoutShareCanvas.exportSize
        )
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage?.pngData()
    }

    @MainActor
    private func saveToPhotos() {
        guard canShare, !isSavingToPhotos else {
            return
        }

        guard let data = renderedPNGData() else {
            exportError = "Couldn't create the image. Please try again."
            return
        }

        isSavingToPhotos = true
        saveMessage = nil

        Task {
            let status = await PHPhotoLibrary
                .requestAuthorization(for: .addOnly)

            guard status == .authorized
                    || status == .limited else {
                await MainActor.run {
                    isSavingToPhotos = false
                    exportError = "Allow Photos access in Settings to save workout images."
                }
                return
            }

            do {
                try await PHPhotoLibrary.shared()
                    .performChanges {
                        let request = PHAssetCreationRequest
                            .forAsset()
                        let options = PHAssetResourceCreationOptions()
                        options.originalFilename = "Athevia-Workout.png"
                        request.addResource(
                            with: .photo,
                            data: data,
                            options: options
                        )
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
    private func exportSticker() {
        guard canShare else {
            return
        }

        isExporting = true
        defer {
            isExporting = false
        }

        guard let data = renderedPNGData() else {
            exportError = "Couldn't create the image. Please try again."
            return
        }

        do {
            let url = FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "Athevia-\(UUID().uuidString).png"
                )

            try data.write(
                to: url,
                options: .atomic
            )
            lastExportURL = url
            exportedFile = WorkoutShareFile(url: url)
        } catch {
            exportError = "Couldn't save the image for sharing. Please try again."
        }
    }

    private func removeExport() {
        if let lastExportURL {
            try? FileManager.default.removeItem(
                at: lastExportURL
            )
        }
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
            let cell: CGFloat = 18

            for row in 0..<Int(
                ceil(size.height / cell)
            ) {
                for column in 0..<Int(
                    ceil(size.width / cell)
                ) {
                    let shade = (
                        row + column
                    ).isMultiple(of: 2)
                        ? Color(white: 0.20)
                        : Color(white: 0.28)

                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * cell,
                                y: CGFloat(row) * cell,
                                width: cell,
                                height: cell
                            )
                        ),
                        with: .color(shade)
                    )
                }
            }
        }
    }
}

private struct WorkoutActivityView:
    UIViewControllerRepresentable {
    let file: URL

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        // Passing the PNG file rather than a UIImage preserves transparency.
        UIActivityViewController(
            activityItems: [file],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}
