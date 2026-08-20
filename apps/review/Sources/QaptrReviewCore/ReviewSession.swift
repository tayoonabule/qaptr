import Foundation

/// The bounded lifecycle phases emitted by the native review-session driver.
public enum ReviewSessionPhase: String, Equatable, Sendable {
    case idle
    case ingesting
    case preparing
    case readyForConsent = "ready_for_consent"
    case analyzing
    case completed
    case failed
    case cancelled
}

/// Scalar metadata shown immediately before captured content may be sent to a provider.
public struct ReviewConsentSummary: Equatable, Sendable {
    public let provider: String
    public let resolvedModel: String?
    public let modelLabel: String
    public let payloadKind: String
    public let captureCount: Int
    public let imageCount: Int
    public let exclusionCount: Int

    public init(
        provider: String,
        resolvedModel: String?,
        modelLabel: String,
        payloadKind: String,
        captureCount: Int,
        imageCount: Int,
        exclusionCount: Int
    ) {
        self.provider = provider
        self.resolvedModel = resolvedModel
        self.modelLabel = modelLabel
        self.payloadKind = payloadKind
        self.captureCount = captureCount
        self.imageCount = imageCount
        self.exclusionCount = exclusionCount
    }
}

/// One scalar snapshot of the native review-session state machine.
public struct ReviewSessionState: Equatable, Sendable {
    public let sessionID: String?
    public let phase: ReviewSessionPhase
    public let capturesSeen: Int
    public let preparedCaptures: Int
    public let imageCount: Int
    public let exclusionCount: Int
    public let observationsWritten: Int
    public let consentSummary: ReviewConsentSummary?
    public let result: String?
    public let outcome: String?
    public let error: String?
    public let resultProvider: String?
    public let resultModelLabel: String?
    public let allowedOperations: Set<String>

    public init(
        sessionID: String?,
        phase: ReviewSessionPhase,
        capturesSeen: Int,
        preparedCaptures: Int,
        imageCount: Int,
        exclusionCount: Int,
        observationsWritten: Int,
        consentSummary: ReviewConsentSummary?,
        result: String?,
        outcome: String?,
        error: String?,
        resultProvider: String?,
        resultModelLabel: String?,
        allowedOperations: Set<String>
    ) {
        self.sessionID = sessionID
        self.phase = phase
        self.capturesSeen = capturesSeen
        self.preparedCaptures = preparedCaptures
        self.imageCount = imageCount
        self.exclusionCount = exclusionCount
        self.observationsWritten = observationsWritten
        self.consentSummary = consentSummary
        self.result = result
        self.outcome = outcome
        self.error = error
        self.resultProvider = resultProvider
        self.resultModelLabel = resultModelLabel
        self.allowedOperations = allowedOperations
    }

    public static let idle = ReviewSessionState(
        sessionID: nil,
        phase: .idle,
        capturesSeen: 0,
        preparedCaptures: 0,
        imageCount: 0,
        exclusionCount: 0,
        observationsWritten: 0,
        consentSummary: nil,
        result: nil,
        outcome: nil,
        error: nil,
        resultProvider: nil,
        resultModelLabel: nil,
        allowedOperations: ["state", "start"]
    )

    public var isTerminal: Bool {
        phase == .completed || phase == .failed || phase == .cancelled
    }
}

/// Strict decoder for the scalar JSON v1 review-session response.
public enum ReviewSessionStateDecoder {
    public static func decode(_ data: Data) throws -> ReviewSessionState {
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ReviewSnapshotDecodeError.unexpectedShape("review session root is not an object")
            }
            root = object
        } catch let error as ReviewSnapshotDecodeError {
            throw error
        } catch {
            throw ReviewSnapshotDecodeError.invalidJSON(String(describing: error))
        }
        guard (root["version"] as? NSNumber)?.intValue == 1 else {
            throw ReviewSnapshotDecodeError.unexpectedShape("review session has an unsupported version")
        }
        guard let ok = root["ok"] as? Bool else {
            throw ReviewSnapshotDecodeError.unexpectedShape("review session is missing ok")
        }
        guard let fields = root["state"] as? [String: Any] else {
            throw ReviewSnapshotDecodeError.unexpectedShape("review session is missing state")
        }
        if !ok {
            let reason = root["error"] as? String ?? "review session operation failed"
            throw ReviewBridgeError.reviewSessionUnavailable(reason)
        }
        return try decodeState(fields)
    }

    private static func decodeState(_ fields: [String: Any]) throws -> ReviewSessionState {
        guard
            let phaseValue = fields["phase"] as? String,
            let phase = ReviewSessionPhase(rawValue: phaseValue),
            let capturesSeen = integer(fields, "captures_seen"),
            let preparedCaptures = integer(fields, "prepared_captures"),
            let imageCount = integer(fields, "image_count"),
            let exclusionCount = integer(fields, "exclusion_count"),
            let observationsWritten = integer(fields, "observations_written"),
            let allowed = fields["allowed_operations"] as? [String]
        else {
            throw ReviewSnapshotDecodeError.unexpectedShape("review session state is missing a required field")
        }
        let consent = try decodeConsent(fields["consent_summary"])
        return ReviewSessionState(
            sessionID: optionalString(fields["session_id"]),
            phase: phase,
            capturesSeen: capturesSeen,
            preparedCaptures: preparedCaptures,
            imageCount: imageCount,
            exclusionCount: exclusionCount,
            observationsWritten: observationsWritten,
            consentSummary: consent,
            result: optionalString(fields["result"]),
            outcome: optionalString(fields["outcome"]),
            error: optionalString(fields["error"]),
            resultProvider: optionalString(fields["result_provider"]),
            resultModelLabel: optionalString(fields["result_model_label"]),
            allowedOperations: Set(allowed)
        )
    }

    private static func decodeConsent(_ value: Any?) throws -> ReviewConsentSummary? {
        guard !(value is NSNull), let value else { return nil }
        guard
            let fields = value as? [String: Any],
            let provider = fields["provider"] as? String,
            let modelLabel = fields["model_label"] as? String,
            let payloadKind = fields["payload_kind"] as? String,
            let captureCount = integer(fields, "capture_count"),
            let imageCount = integer(fields, "image_count"),
            let exclusionCount = integer(fields, "exclusion_count")
        else {
            throw ReviewSnapshotDecodeError.unexpectedShape("review consent summary is missing a required field")
        }
        return ReviewConsentSummary(
            provider: provider,
            resolvedModel: optionalString(fields["resolved_model"]),
            modelLabel: modelLabel,
            payloadKind: payloadKind,
            captureCount: captureCount,
            imageCount: imageCount,
            exclusionCount: exclusionCount
        )
    }

    private static func integer(_ fields: [String: Any], _ key: String) -> Int? {
        (fields[key] as? NSNumber)?.intValue
    }

    private static func optionalString(_ value: Any?) -> String? {
        guard !(value is NSNull) else { return nil }
        return value as? String
    }
}
