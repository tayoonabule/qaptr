import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import QaptrHelperCore

struct ScreenCaptureAdapter: ImageCapture, CaptureStartupPreflight {
    func screenRecordingAccessGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func capture(displayID: String, maxDimension: Int) throws -> CapturedFrame {
        let content = try currentShareableContent()
        guard let numericID = CGDirectDisplayID(displayID),
              let display = content.displays.first(where: { $0.displayID == numericID })
        else {
            throw ScreenCaptureError.displayUnavailable(displayID)
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let sourceWidth = max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
        let sourceHeight = max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
        let sourceLargest = max(sourceWidth, sourceHeight)
        let scale = min(1, Double(maxDimension) / Double(sourceLargest))
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.queueDepth = 1
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true

        let image = try captureImage(filter: filter, configuration: configuration)
        guard let data = pngData(for: image) else {
            throw ScreenCaptureError.encodingFailed
        }
        return try CapturedFrame(imageData: data, width: image.width, height: image.height)
    }

    func availableDisplayIDs() throws -> [String] {
        try currentShareableContent().displays.map { String($0.displayID) }.sorted()
    }

    private func currentShareableContent() throws -> SCShareableContent {
        let result = CallbackResult<SCShareableContent>()
        let completed = DispatchSemaphore(value: 0)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
            if let content {
                result.complete(.success(content))
            } else {
                result.complete(.failure(ScreenCaptureError.framework(error?.localizedDescription ?? "no content")))
            }
            completed.signal()
        }
        guard completed.wait(timeout: .now() + 5) == .success else {
            throw ScreenCaptureError.timedOut("display enumeration")
        }
        guard let value = result.take() else {
            throw ScreenCaptureError.framework("display enumeration returned no result")
        }
        return try value.get()
    }

    private func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) throws -> CGImage {
        let result = CallbackResult<CGImage>()
        let completed = DispatchSemaphore(value: 0)
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
            if let image {
                result.complete(.success(image))
            } else {
                result.complete(.failure(ScreenCaptureError.framework(error?.localizedDescription ?? "no image")))
            }
            completed.signal()
        }
        guard completed.wait(timeout: .now() + 5) == .success else {
            throw ScreenCaptureError.timedOut("one-shot capture")
        }
        guard let value = result.take() else {
            throw ScreenCaptureError.framework("capture returned no result")
        }
        return try value.get()
    }

    private func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}

private final class CallbackResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func complete(_ result: Result<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard self.result == nil else {
            return
        }
        self.result = result
    }

    func take() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

private enum ScreenCaptureError: Error, CustomStringConvertible {
    case displayUnavailable(String)
    case encodingFailed
    case framework(String)
    case timedOut(String)

    var description: String {
        switch self {
        case let .displayUnavailable(displayID):
            "display \(displayID) is unavailable"
        case .encodingFailed:
            "captured image could not be encoded"
        case let .framework(message):
            "ScreenCaptureKit failed: \(message)"
        case let .timedOut(operation):
            "timed out waiting for \(operation)"
        }
    }
}
