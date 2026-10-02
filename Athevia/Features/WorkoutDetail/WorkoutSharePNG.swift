import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// One validated PNG is used for the preview and every export destination.
/// UIImage is only a decoded preview; it is never offered as an export payload.
struct WorkoutSharePNG: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage

    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              type as String == UTType.png.identifier,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              Self.hasTransparentBackground(cgImage) else {
            return nil
        }
        self.data = data
        self.image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let pngData = data
        provider.suggestedName = "Athevia-Workout.png"
        // Register only the original PNG. Offering UIImage or JPEG as another
        // representation lets a recipient negotiate away the alpha channel.
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(pngData, nil)
            return nil
        }
        return provider
    }

    @MainActor
    func copy(to pasteboard: UIPasteboard) {
        pasteboard.setData(data, forPasteboardType: UTType.png.identifier)
    }

    private static func hasTransparentBackground(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }

        let width = image.width
        let height = image.height
        guard width > 1, height > 1 else {
            return false
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let byteCount = bytesPerRow * height
        var pixels = [UInt8](
            repeating: 0,
            count: byteCount
        )

        guard let colorSpace = CGColorSpace(
            name: CGColorSpace.sRGB
        ) else {
            return false
        }

        return pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo:
                        CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                  ) else {
                return false
            }

            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: width,
                    height: height
                )
            )

            let bytes = buffer.bindMemory(to: UInt8.self)

            func alpha(
                x: Int,
                y: Int
            ) -> UInt8 {
                let offset = y * bytesPerRow + x * bytesPerPixel
                return bytes[offset + 3]
            }

            let corners = [
                alpha(x: 0, y: 0),
                alpha(x: width - 1, y: 0),
                alpha(x: 0, y: height - 1),
                alpha(x: width - 1, y: height - 1)
            ]

            guard corners.allSatisfy({ $0 == 0 }) else {
                return false
            }

            // The share asset is a sticker on a transparent canvas, so most
            // sampled background pixels should remain fully transparent.
            var transparentSamples = 0
            var sampleCount = 0
            let columns = 12
            let rows = 20

            for column in 0..<columns {
                for row in 0..<rows {
                    let x = min(
                        width - 1,
                        column * (width - 1) / max(columns - 1, 1)
                    )
                    let y = min(
                        height - 1,
                        row * (height - 1) / max(rows - 1, 1)
                    )

                    if alpha(x: x, y: y) == 0 {
                        transparentSamples += 1
                    }
                    sampleCount += 1
                }
            }

            // Reject a blank PNG as well as an opaque or flattened one.
            let hasContent = stride(from: 3, to: byteCount, by: bytesPerPixel)
                .contains { bytes[$0] > 0 }
            return hasContent && sampleCount > 0
                && Double(transparentSamples) / Double(sampleCount) >= 0.60
        }
    }
}

/// Files receives the original encoded bytes, without an image conversion.
struct WorkoutSharePNGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
