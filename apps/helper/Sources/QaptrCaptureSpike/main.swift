import CoreGraphics
import Foundation
import ScreenCaptureKit

private struct Options {
    let intervalSeconds: TimeInterval
    let maxDimension: Int
    let maximumCycles: Int?

    static func parse(_ arguments: ArraySlice<String>) throws -> Self {
        var intervalSeconds: TimeInterval = 600
        var maxDimension = 1_920
        var maximumCycles: Int?
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            index = arguments.index(after: index)
            guard index < arguments.endIndex else {
                throw SpikeError.missingValue(argument)
            }
            let value = arguments[index]
            index = arguments.index(after: index)

            switch argument {
            case "--interval-seconds":
                guard let parsed = TimeInterval(value), parsed > 0 else {
                    throw SpikeError.invalidValue(argument, value)
                }
                intervalSeconds = parsed
            case "--max-dimension":
                guard let parsed = Int(value), parsed > 0 else {
                    throw SpikeError.invalidValue(argument, value)
                }
                maxDimension = parsed
            case "--cycles":
                guard let parsed = Int(value), parsed > 0 else {
                    throw SpikeError.invalidValue(argument, value)
                }
                maximumCycles = parsed
            default:
                throw SpikeError.unknownArgument(argument)
            }
        }

        return Self(
            intervalSeconds: intervalSeconds,
            maxDimension: maxDimension,
            maximumCycles: maximumCycles
        )
    }
}

private enum SpikeError: Error, CustomStringConvertible {
    case captureReturnedNoImage
    case frameworkFailure(String)
    case invalidValue(String, String)
    case missingValue(String)
    case noDisplays
    case timedOut(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .captureReturnedNoImage:
            "ScreenCaptureKit returned no image"
        case let .frameworkFailure(message):
            "ScreenCaptureKit failed: \(message)"
        case let .invalidValue(argument, value):
            "invalid value for \(argument): \(value)"
        case let .missingValue(argument):
            "missing value for \(argument)"
        case .noDisplays:
            "ScreenCaptureKit reported no displays"
        case let .timedOut(operation):
            "timed out waiting for \(operation)"
        case let .unknownArgument(argument):
            "unknown argument: \(argument)"
        }
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

private struct OutputSize {
    let width: Int
    let height: Int
}

private struct CaptureResult {
    let latencyMilliseconds: Double
    let outputSize: OutputSize
    let sourceSize: OutputSize
}

private func sourceSize(for filter: SCContentFilter) -> OutputSize {
    OutputSize(
        width: max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())),
        height: max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
    )
}

private func outputSize(for sourceSize: OutputSize, maxDimension: Int) -> OutputSize {
    let sourceWidth = sourceSize.width
    let sourceHeight = sourceSize.height
    let largestDimension = max(sourceWidth, sourceHeight)
    let scale = min(1, Double(maxDimension) / Double(largestDimension))

    return OutputSize(
        width: max(1, Int((Double(sourceWidth) * scale).rounded())),
        height: max(1, Int((Double(sourceHeight) * scale).rounded()))
    )
}

private func currentShareableContent() throws -> SCShareableContent {
    let callbackResult = CallbackResult<SCShareableContent>()
    let completed = DispatchSemaphore(value: 0)
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
        if let content {
            callbackResult.complete(.success(content))
        } else {
            callbackResult.complete(
                .failure(SpikeError.frameworkFailure(error?.localizedDescription ?? "no content"))
            )
        }
        completed.signal()
    }

    guard completed.wait(timeout: .now() + 5) == .success else {
        throw SpikeError.timedOut("display enumeration")
    }
    guard let result = callbackResult.take() else {
        throw SpikeError.frameworkFailure("display enumeration returned no result")
    }
    return try result.get()
}

private func capture(display: SCDisplay, maxDimension: Int) throws -> CaptureResult {
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let inputSize = sourceSize(for: filter)
    let size = outputSize(for: inputSize, maxDimension: maxDimension)
    let configuration = SCStreamConfiguration()
    configuration.width = size.width
    configuration.height = size.height
    configuration.queueDepth = 1
    configuration.showsCursor = false
    configuration.scalesToFit = true
    configuration.preservesAspectRatio = true

    let started = ContinuousClock.now
    let callbackResult = CallbackResult<CGImage>()
    let completed = DispatchSemaphore(value: 0)
    SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: configuration
    ) { image, error in
        if let image {
            callbackResult.complete(.success(image))
        } else {
            callbackResult.complete(
                .failure(SpikeError.frameworkFailure(error?.localizedDescription ?? "no image"))
            )
        }
        completed.signal()
    }
    guard completed.wait(timeout: .now() + 5) == .success else {
        throw SpikeError.timedOut("one-shot capture")
    }
    guard let image = try callbackResult.take()?.get() else {
        throw SpikeError.captureReturnedNoImage
    }
    let elapsed = ContinuousClock.now - started
    guard image.width > 0, image.height > 0 else {
        throw SpikeError.captureReturnedNoImage
    }

    return CaptureResult(
        latencyMilliseconds: elapsed.milliseconds,
        outputSize: OutputSize(width: image.width, height: image.height),
        sourceSize: inputSize
    )
}

private func isScreenLocked() -> Bool {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
        return false
    }
    return session["CGSSessionScreenIsLocked"] as? Bool ?? false
}

private func selectedDisplays(
    from availableDisplays: [SCDisplay],
    selectedIDs: Set<CGDirectDisplayID>
) -> [SCDisplay] {
    availableDisplays
        .filter { selectedIDs.contains($0.displayID) }
        .sorted { $0.displayID < $1.displayID }
}

private func logCapture(mode: String, display: SCDisplay, result: CaptureResult) {
    print(
        "event=capture mode=\(mode) display_id=\(display.displayID) "
            + "latency_ms=\(String(format: "%.3f", result.latencyMilliseconds)) "
            + "source=\(result.sourceSize.width)x\(result.sourceSize.height) "
            + "output=\(result.outputSize.width)x\(result.outputSize.height)"
    )
}

private func runCaptureSet(
    mode: String,
    displays: [SCDisplay],
    maxDimension: Int
) throws -> Double {
    let started = ContinuousClock.now
    for display in displays {
        let result = try capture(display: display, maxDimension: maxDimension)
        logCapture(mode: mode, display: display, result: result)
    }
    return (ContinuousClock.now - started).milliseconds
}

private extension Duration {
    var milliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

@main
private enum QaptrCaptureSpike {
    static func main() {
        do {
            let options = try Options.parse(CommandLine.arguments.dropFirst())
            try run(options: options)
        } catch {
            FileHandle.standardError.write(Data("capture spike failed: \(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func run(options: Options) throws {
        let initialContent = try currentShareableContent()
        let selectedIDs = Set(initialContent.displays.map(\.displayID))
        guard !selectedIDs.isEmpty else {
            throw SpikeError.noDisplays
        }

        let selectedList = selectedIDs.sorted().map(String.init).joined(separator: ",")
        print(
            "event=start pid=\(ProcessInfo.processInfo.processIdentifier) "
                + "selected_display_ids=\(selectedList) max_dimension=\(options.maxDimension) "
                + "interval_seconds=\(String(format: "%.3f", options.intervalSeconds))"
        )

        var cycle = 0
        while options.maximumCycles.map({ cycle < $0 }) ?? true {
            cycle += 1
            if isScreenLocked() {
                print("event=skip cycle=\(cycle) reason=screen_locked")
            } else {
                let tickStarted = ContinuousClock.now
                let content = try currentShareableContent()
                let displays = selectedDisplays(
                    from: content.displays,
                    selectedIDs: selectedIDs
                )
                let missingCount = selectedIDs.count - displays.count

                if displays.isEmpty {
                    print("event=skip cycle=\(cycle) reason=selected_displays_unavailable")
                } else {
                    let singleLatency = try runCaptureSet(
                        mode: "single",
                        displays: Array(displays.prefix(1)),
                        maxDimension: options.maxDimension
                    )
                    let multipleLatency = try runCaptureSet(
                        mode: "multiple",
                        displays: displays,
                        maxDimension: options.maxDimension
                    )
                    let tickLatency = (ContinuousClock.now - tickStarted).milliseconds
                    print(
                        "event=tick cycle=\(cycle) displays=\(displays.count) "
                            + "missing_selected=\(missingCount) "
                            + "single_latency_ms=\(String(format: "%.3f", singleLatency)) "
                            + "multiple_latency_ms=\(String(format: "%.3f", multipleLatency)) "
                            + "latency_ms=\(String(format: "%.3f", tickLatency))"
                    )
                }
            }
            fflush(stdout)

            if options.maximumCycles.map({ cycle >= $0 }) ?? false {
                break
            }
            Thread.sleep(forTimeInterval: options.intervalSeconds)
        }
    }
}
