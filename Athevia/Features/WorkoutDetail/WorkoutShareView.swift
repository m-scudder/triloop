import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum WorkoutShareLayout: String, CaseIterable, Identifiable {
    case centered
    case side
    case compact

    var id: String { rawValue }
}

private enum WorkoutShareCanvas {
    static let exportSize = CGSize(width: 1080, height: 1920)
}

@MainActor
struct WorkoutSharePNGRenderer {
    let snapshot: WorkoutShareSnapshot
    let layout: WorkoutShareLayout
    let route: WorkoutShareRoute

    private let orange = UIColor(
        red: 1.00,
        green: 0.42,
        blue: 0.16,
        alpha: 1
    )

    func pngData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(
            size: WorkoutShareCanvas.exportSize,
            format: format
        )

        return renderer.pngData { rendererContext in
            let context = rendererContext.cgContext
            context.clear(
                CGRect(
                    origin: .zero,
                    size: WorkoutShareCanvas.exportSize
                )
            )

            switch layout {
            case .centered:
                drawCentered(in: context)
            case .side:
                drawSide(in: context)
            case .compact:
                drawCompact(in: context)
            }
        }
    }

    private func drawCentered(in context: CGContext) {
        var y: CGFloat

        if route.hasRoute {
            drawRoute(
                in: CGRect(
                    x: 130,
                    y: 250,
                    width: 820,
                    height: 650
                ),
                context: context
            )
            y = 980
        } else {
            y = 570
        }

        for item in snapshot.metrics {
            y = drawMetric(
                item,
                x: 140,
                y: y,
                width: 800,
                alignment: .center,
                valueSize: 66
            ) + 34
        }

        drawSportMark(
            center: CGPoint(
                x: WorkoutShareCanvas.exportSize.width / 2,
                y: y + 42
            )
        )

        drawBrand(
            in: CGRect(
                x: 140,
                y: y + 92,
                width: 800,
                height: 60
            ),
            alignment: .center
        )
    }

    private func drawSide(in context: CGContext) {
        let contentTop: CGFloat = 610

        if route.hasRoute {
            drawRoute(
                in: CGRect(
                    x: 70,
                    y: contentTop,
                    width: 470,
                    height: 560
                ),
                context: context
            )
        } else {
            drawSportMark(
                center: CGPoint(
                    x: 290,
                    y: contentTop + 275
                ),
                pointSize: 86
            )
        }

        let rightX: CGFloat = 610
        let rightWidth: CGFloat = 390

        drawBrand(
            in: CGRect(
                x: rightX,
                y: contentTop,
                width: rightWidth,
                height: 60
            ),
            alignment: .left
        )

        var y = contentTop + 105
        for item in snapshot.metrics {
            y = drawMetric(
                item,
                x: rightX,
                y: y,
                width: rightWidth,
                alignment: .left,
                valueSize: 48
            ) + 30
        }
    }

    private func drawCompact(in context: CGContext) {
        let top: CGFloat = 610

        drawBrand(
            in: CGRect(
                x: 115,
                y: top,
                width: 330,
                height: 60
            ),
            alignment: .left
        )

        _ = drawText(
            snapshot.title,
            in: CGRect(
                x: 115,
                y: top + 75,
                width: 330,
                height: 75
            ),
            font: roundedFont(
                size: 52,
                weight: .bold
            ),
            color: .white,
            alignment: .left
        )

        _ = drawText(
            TrainingFormatter.shortDate(
                snapshot.date,
                includeYear: true
            ),
            in: CGRect(
                x: 115,
                y: top + 155,
                width: 330,
                height: 45
            ),
            font: .systemFont(
                ofSize: 24,
                weight: .medium
            ),
            color: UIColor.white.withAlphaComponent(0.78),
            alignment: .left
        )

        var y = top
        for item in snapshot.metrics {
            y = drawMetric(
                item,
                x: 560,
                y: y,
                width: 390,
                alignment: .left,
                valueSize: 46
            ) + 28
        }

        if route.hasRoute {
            drawRoute(
                in: CGRect(
                    x: 180,
                    y: 1080,
                    width: 720,
                    height: 500
                ),
                context: context
            )
        } else {
            drawSportMark(
                center: CGPoint(
                    x: WorkoutShareCanvas.exportSize.width / 2,
                    y: 1120
                ),
                pointSize: 72
            )
        }
    }

    @discardableResult
    private func drawMetric(
        _ item: WorkoutShareMetric,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        alignment: NSTextAlignment,
        valueSize: CGFloat
    ) -> CGFloat {
        let label = item.label
            .replacingOccurrences(of: " · ", with: " ")

        let labelHeight = drawText(
            label,
            in: CGRect(
                x: x,
                y: y,
                width: width,
                height: 42
            ),
            font: .systemFont(
                ofSize: 25,
                weight: .semibold
            ),
            color: UIColor.white.withAlphaComponent(0.88),
            alignment: alignment
        )

        let valueHeight = drawText(
            displayValue(for: item),
            in: CGRect(
                x: x,
                y: y + labelHeight + 5,
                width: width,
                height: 86
            ),
            font: roundedFont(
                size: valueSize,
                weight: .bold
            ),
            color: .white,
            alignment: alignment
        )

        return y + labelHeight + 5 + valueHeight
    }

    private func drawRoute(
        in rect: CGRect,
        context: CGContext
    ) {
        let fitted = route.fittedSegments(
            in: rect.size,
            inset: 30
        )

        context.saveGState()
        context.translateBy(
            x: rect.minX,
            y: rect.minY
        )
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for segment in fitted {
            guard let first = segment.first else {
                continue
            }

            let path = CGMutablePath()
            path.move(to: first)
            for point in segment.dropFirst() {
                path.addLine(to: point)
            }

            context.addPath(path)
            context.setStrokeColor(
                UIColor.black.withAlphaComponent(0.25).cgColor
            )
            context.setLineWidth(18)
            context.strokePath()

            context.addPath(path)
            context.setStrokeColor(orange.cgColor)
            context.setLineWidth(11)
            context.strokePath()
        }

        context.restoreGState()
    }

    private func drawSportMark(
        center: CGPoint,
        pointSize: CGFloat = 54
    ) {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .semibold
        )

        guard let symbol = UIImage(
            systemName: snapshot.discipline.symbolName,
            withConfiguration: configuration
        )?.withTintColor(
            orange,
            renderingMode: .alwaysOriginal
        ) else {
            return
        }

        let origin = CGPoint(
            x: center.x - symbol.size.width / 2,
            y: center.y - symbol.size.height / 2
        )
        symbol.draw(at: origin)
    }

    private func drawBrand(
        in rect: CGRect,
        alignment: NSTextAlignment
    ) {
        _ = drawText(
            "ATHEVIA",
            in: rect,
            font: roundedFont(
                size: 38,
                weight: .black
            ),
            color: .white,
            alignment: alignment,
            kern: 1.8
        )
    }

    @discardableResult
    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment,
        kern: CGFloat = 0
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: kern
        ]

        let string = NSAttributedString(
            string: text,
            attributes: attributes
        )
        let measured = string.boundingRect(
            with: CGSize(
                width: rect.width,
                height: rect.height
            ),
            options: [
                .usesLineFragmentOrigin,
                .usesFontLeading
            ],
            context: nil
        )

        string.draw(
            in: CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: min(
                    rect.height,
                    ceil(measured.height)
                )
            )
        )

        return ceil(measured.height)
    }

    private func roundedFont(
        size: CGFloat,
        weight: UIFont.Weight
    ) -> UIFont {
        let base = UIFont.systemFont(
            ofSize: size,
            weight: weight
        )
        guard let descriptor = base.fontDescriptor
            .withDesign(.rounded) else {
            return base
        }
        return UIFont(
            descriptor: descriptor,
            size: size
        )
    }

    private func displayValue(
        for item: WorkoutShareMetric
    ) -> String {
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
    @State private var exportedPNG: WorkoutSharePNG?
    @State private var previews: [WorkoutShareLayout: WorkoutSharePNG] = [:]
    @State private var exportError: String?
    @State private var isSavingToPhotos = false
    @State private var saveMessage: String?

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
        !isLoadingRoute && !isSavingToPhotos
            && exportedPNG == nil && previews[layout] != nil
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
                guard !Task.isCancelled else { return }
                preparePreviews()
            }
            .sheet(item: $exportedPNG) { png in
                WorkoutActivityView(png: png)
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

            Group {
                if let png = previews[layout] {
                    // Decode the exact PNG that Save, Copy and Share deliver.
                    // The checkerboard belongs only to this preview container.
                    Image(uiImage: png.image)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
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
                        isSavingToPhotos ? "Saving…" : "Save PNG",
                        systemImage: "arrow.down.circle"
                    )
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(!canShare)

                Button(action: exportSticker) {
                    Label(
                        "Share",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(!canShare)
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
    private func preparePreviews() {
        var rendered: [WorkoutShareLayout: WorkoutSharePNG] = [:]
        for candidate in WorkoutShareLayout.allCases {
            let data = WorkoutSharePNGRenderer(
                snapshot: snapshot,
                layout: candidate,
                route: route
            ).pngData()
            guard let png = WorkoutSharePNG(data: data) else {
                previews = [:]
                exportError = "Couldn't create a transparent PNG. Please try again."
                return
            }
            rendered[candidate] = png
        }
        previews = rendered
    }

    @MainActor
    private func saveToPhotos() {
        guard canShare, !isSavingToPhotos else {
            return
        }

        guard let png = previews[layout] else { return }
        let data = png.data

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Athevia-Workout-\(UUID().uuidString).png"
            )

        do {
            // Persist the exact encoded PNG first. Photos then imports this
            // file resource directly instead of receiving image data that may
            // be reinterpreted by an intermediate image conversion path.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            exportError = "Couldn't create the PNG file. Please try again."
            return
        }

        isSavingToPhotos = true
        saveMessage = nil

        Task {
            defer {
                try? FileManager.default.removeItem(at: fileURL)
            }

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
                        let request = PHAssetCreationRequest.forAsset()
                        let options = PHAssetResourceCreationOptions()
                        options.originalFilename = fileURL.lastPathComponent
                        options.uniformTypeIdentifier = UTType.png.identifier
                        options.shouldMoveFile = false

                        request.addResource(
                            with: .photo,
                            fileURL: fileURL,
                            options: options
                        )
                    }

                await MainActor.run {
                    isSavingToPhotos = false
                    saveMessage = "Transparent PNG saved to Photos."
                }
            } catch {
                await MainActor.run {
                    isSavingToPhotos = false
                    exportError = "Couldn't save the PNG to Photos. Please try again."
                }
            }
        }
    }

    @MainActor
    private func exportSticker() {
        guard canShare, let png = previews[layout] else { return }
        saveMessage = nil
        exportedPNG = png
    }
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
    let png: WorkoutSharePNG

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        let configuration = UIActivityItemsConfiguration(
            itemProviders: [png.itemProvider()]
        )
        let controller = UIActivityViewController(activityItemsConfiguration: configuration)
        // Use the explicit PNG Save/Copy actions above. The generic activities
        // may negotiate a UIImage representation or copy a file URL instead.
        controller.excludedActivityTypes = [.saveToCameraRoll, .copyToPasteboard]
        return controller
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context
    ) {}
}

