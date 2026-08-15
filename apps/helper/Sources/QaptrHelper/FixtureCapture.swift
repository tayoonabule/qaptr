import CoreGraphics
import Foundation
import ImageIO
import QaptrHelperCore

/// Reads committed fixture images for the helper's deterministic ingestion mode.
/// The returned bytes go directly to the sealer and are never written to the
/// scalar capture-progress record.
struct FixtureImageCapture: ImageCapture {
    let root: URL

    func capture(displayID: String, maxDimension: Int) throws -> CapturedFrame {
        let baseURL = root.appendingPathComponent(displayID, isDirectory: false)
        let imageURL = baseURL.pathExtension.isEmpty
            ? baseURL.appendingPathExtension("png")
            : baseURL
        let data = try Data(contentsOf: imageURL)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) <= maxDimension else {
            throw FixtureImageCaptureError.invalidImage(displayID)
        }
        return try CapturedFrame(imageData: data, width: width, height: height)
    }
}

enum FixtureImageCaptureError: Error, CustomStringConvertible {
    case invalidImage(String)

    var description: String {
        switch self {
        case let .invalidImage(source):
            "fixture image is invalid or exceeds the configured max dimension: \(source)"
        }
    }
}
