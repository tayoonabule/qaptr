import Foundation

/// The non-invasive installation result for one local CLI provider.
public enum ProviderInstallationState: String, Equatable, Sendable {
    case detected
    case notInstalled = "not_installed"
    case unavailable
}

/// A scalar provider readiness result.
///
/// `detected` means only that an executable was found. It never means the
/// provider is authenticated or usable.
public struct ProviderReadiness: Equatable, Sendable {
    public let id: String
    public let state: ProviderInstallationState
    public let usable: Bool

    public init(id: String, state: ProviderInstallationState, usable: Bool) {
        self.id = id
        self.state = state
        self.usable = usable
    }
}

/// The bounded provider readiness snapshot returned by qaptr-review-ffi.
public struct ProviderReadinessSnapshot: Equatable, Sendable {
    public let providers: [ProviderReadiness]

    public init(providers: [ProviderReadiness]) {
        self.providers = providers
    }
}

/// Decodes the JSON produced by `qaptr_provider_readiness_json`.
public enum ProviderReadinessDecoder {
    public static func decode(_ data: Data) throws -> ProviderReadinessSnapshot {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ReviewSnapshotDecodeError.invalidJSON(String(describing: error))
        }
        guard let root = json as? [String: Any] else {
            throw ReviewSnapshotDecodeError.unexpectedShape("root is not an object")
        }
        guard let version = (root["version"] as? NSNumber)?.intValue, version == 1 else {
            throw ReviewSnapshotDecodeError.unexpectedShape("readiness has an unsupported version")
        }
        guard let providerFields = root["providers"] as? [[String: Any]] else {
            throw ReviewSnapshotDecodeError.unexpectedShape("readiness missing a \"providers\" array")
        }

        let providers = try providerFields.map { fields in
            guard
                let id = fields["id"] as? String,
                let rawState = fields["state"] as? String,
                let state = ProviderInstallationState(rawValue: rawState),
                let usable = fields["usable"] as? Bool
            else {
                throw ReviewSnapshotDecodeError.unexpectedShape("provider readiness missing a required field")
            }
            guard !usable else {
                throw ReviewSnapshotDecodeError.unexpectedShape("path-only readiness cannot claim usability")
            }
            return ProviderReadiness(id: id, state: state, usable: usable)
        }
        return ProviderReadinessSnapshot(providers: providers)
    }
}
