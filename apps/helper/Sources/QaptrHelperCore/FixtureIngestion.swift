import Foundation

/// One capture described by a deterministic fixture manifest.
public struct FixtureCaptureRecord: Equatable, Sendable {
    public let captureID: String
    public let source: String
    public let capturedAtMillis: Int64

    public init(captureID: String, source: String, capturedAtMillis: Int64) throws {
        guard Self.isSafeIdentifier(captureID) else {
            throw FixtureManifestError.invalidCaptureID(captureID)
        }
        guard Self.isSafeRelativePath(source) else {
            throw FixtureManifestError.invalidSource(source)
        }
        guard capturedAtMillis >= 0 else {
            throw FixtureManifestError.invalidTimestamp(String(capturedAtMillis))
        }
        self.captureID = captureID
        self.source = source
        self.capturedAtMillis = capturedAtMillis
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "\\" })
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\") else {
            return false
        }
        return !value.split(separator: "/").contains { $0 == "." || $0 == ".." }
    }
}

public enum FixtureManifestError: Error, Equatable, Sendable {
    case invalidHeader
    case emptyManifest
    case malformedRow(Int)
    case duplicateCaptureID(String)
    case invalidCaptureID(String)
    case invalidSource(String)
    case invalidTimestamp(String)
}

/// A CSV fixture manifest. It contains capture metadata only; image bytes stay
/// behind the ImageCapture and BundleSealer boundaries.
public struct FixtureManifest: Equatable, Sendable {
    public let records: [FixtureCaptureRecord]

    public init(csv: String) throws {
        let lines = csv.split(whereSeparator: { $0.isNewline }).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            == "capture_id,source,captured_at_ms" else {
            throw FixtureManifestError.invalidHeader
        }

        var seen = Set<String>()
        var records = [FixtureCaptureRecord]()
        for (offset, rawLine) in lines.dropFirst().enumerated() {
            let lineNumber = offset + 2
            let fields = rawLine.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard fields.count == 3,
                  let capturedAtMillis = Int64(fields[2]) else {
                throw FixtureManifestError.malformedRow(lineNumber)
            }
            let captureID = fields[0]
            guard !seen.contains(captureID) else {
                throw FixtureManifestError.duplicateCaptureID(captureID)
            }
            let record = try FixtureCaptureRecord(
                captureID: captureID,
                source: fields[1],
                capturedAtMillis: capturedAtMillis
            )
            seen.insert(record.captureID)
            records.append(record)
        }
        guard !records.isEmpty else {
            throw FixtureManifestError.emptyManifest
        }
        self.records = records
    }

    public init(data: Data) throws {
        try self.init(csv: String(decoding: data, as: UTF8.self))
    }
}

public struct FixtureIngestionResult: Equatable, Sendable {
    public let attemptedCount: Int
    public let sealedCount: Int
    public let failedCount: Int

    public init(attemptedCount: Int, sealedCount: Int, failedCount: Int) {
        self.attemptedCount = attemptedCount
        self.sealedCount = sealedCount
        self.failedCount = failedCount
    }
}

/// Runs a deterministic fixture session through the same capture and sealing
/// boundaries as the helper. Only CaptureProgress is durable outside the vault.
public enum FixtureIngestion {
    public static func run(
        manifest: FixtureManifest,
        capture: ImageCapture,
        sealer: BundleSealer,
        context: SampledContext,
        progressStore: CaptureProgressStore,
        intervalSeconds: Int,
        maxDimension: Int,
        processID: Int64,
        at timestampMillis: Int64
    ) throws -> FixtureIngestionResult {
        guard (CaptureInterval.minimumSeconds...CaptureInterval.maximumSeconds).contains(intervalSeconds),
              intervalSeconds.isMultiple(of: CaptureInterval.stepSeconds) else {
            throw CaptureCoreError.invalidInterval(TimeInterval(intervalSeconds))
        }
        guard maxDimension > 0 else {
            throw CaptureCoreError.captureFailed("invalid fixture max dimension")
        }

        var tracker = CaptureProgressTracker()
        tracker.start(
            at: timestampMillis,
            processID: processID,
            selectedDisplayIDs: ["fixture"],
            activeIntervalSeconds: intervalSeconds
        )
        try progressStore.write(tracker.progress)

        var sealedCount = 0
        var failedCount = 0
        for record in manifest.records {
            tracker.beginCapture(
                at: timestampMillis,
                selectedDisplayIDs: ["fixture"],
                activeIntervalSeconds: intervalSeconds
            )
            try progressStore.write(tracker.progress)

            do {
                let frame = try capture.capture(displayID: record.source, maxDimension: maxDimension)
                try sealer.seal(captureID: record.captureID, frame: frame, context: context)
                sealedCount += 1
                tracker.finishCapture(
                    at: timestampMillis,
                    successfulCaptures: 1,
                    selectedDisplayIDs: ["fixture"],
                    activeIntervalSeconds: intervalSeconds
                )
            } catch {
                failedCount += 1
                tracker.finishCapture(
                    at: timestampMillis,
                    successfulCaptures: 0,
                    selectedDisplayIDs: ["fixture"],
                    activeIntervalSeconds: intervalSeconds,
                    failureReason: "fixture capture failed: \(error)"
                )
            }
            try progressStore.write(tracker.progress)
        }

        return FixtureIngestionResult(
            attemptedCount: manifest.records.count,
            sealedCount: sealedCount,
            failedCount: failedCount
        )
    }
}
