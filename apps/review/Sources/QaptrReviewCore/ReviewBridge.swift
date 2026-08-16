import Foundation

/// Errors raised while talking to the native `qaptr-review-ffi` bridge.
public enum ReviewBridgeError: Error, CustomStringConvertible, Equatable {
    case libraryUnavailable
    case symbolMissing(String)
    case secureBootstrapUnavailable(String)
    case storeUnavailable
    case snapshotUnavailable(String)
    case providerReadinessUnavailable(String)
    case documentOperationFailed(String)

    public var description: String {
        switch self {
        case .libraryUnavailable:
            "the qaptr-review-ffi library could not be loaded"
        case let .symbolMissing(name):
            "missing bridge symbol: \(name)"
        case let .secureBootstrapUnavailable(reason):
            "secure capture setup unavailable: \(reason)"
        case .storeUnavailable:
            "the durable history store could not be opened"
        case let .snapshotUnavailable(reason):
            "durable history snapshot unavailable: \(reason)"
        case let .providerReadinessUnavailable(reason):
            "provider readiness unavailable: \(reason)"
        case let .documentOperationFailed(reason):
            "document operation failed: \(reason)"
        }
    }
}

private typealias StoreOpenFunction = @convention(c) (UnsafeRawPointer?, Int) -> UnsafeMutableRawPointer?
private typealias StoreDestroyFunction = @convention(c) (UnsafeMutableRawPointer) -> Void
private typealias StoreSnapshotFunction = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeMutableRawPointer?,
    Int
) -> Int
private typealias StoreLastErrorFunction = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeMutableRawPointer?,
    Int
) -> Int
private typealias ReviewStatusFunction = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeMutableRawPointer?,
    Int
) -> Int
private typealias ProviderReadinessFunction = @convention(c) (
    UnsafeMutableRawPointer?,
    Int
) -> Int
/// Shared shape for `qaptr_observation_detail_json`,
/// `qaptr_workflow_generate_json`, and `qaptr_workflow_export_json`: a store
/// handle, a bounded JSON v1 request, and the same two-pass output contract
/// as every other scalar JSON bridge call.
private typealias DocumentBridgeFunction = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeRawPointer?,
    Int,
    UnsafeMutableRawPointer?,
    Int
) -> Int
private typealias KeyBootstrapFunction = @convention(c) (
    UnsafeRawPointer?,
    Int,
    UnsafeRawPointer?,
    Int,
    UnsafeMutableRawPointer?,
    Int
) -> Int
private typealias PermissionStateFunction = @convention(c) (
    UnsafeRawPointer?,
    Int,
    Int32
) -> Int32
private typealias PermissionRequestFunction = @convention(c) (
    UnsafeRawPointer?,
    Int,
    Int32
) -> Int32
private typealias LoginItemStatusFunction = @convention(c) () -> Int32
private typealias LoginItemSetEnabledFunction = @convention(c) (Int32) -> Int32

enum ReviewFFILibraryPath {
    static let fileName = "libqaptr_review_ffi.dylib"

    static func candidates(environment: [String: String], bundle: Bundle) -> [String] {
        var paths: [String] = []
        if let path = environment["QAPTR_REVIEW_FFI_LIBRARY_PATH"], !path.isEmpty {
            paths.append(path)
        }
        if let directory = environment["QAPTR_REVIEW_FFI_LIBRARY_DIR"], !directory.isEmpty {
            paths.append(URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(fileName).path)
        }
        if let privateFrameworksPath = bundle.privateFrameworksPath {
            paths.append(URL(fileURLWithPath: privateFrameworksPath, isDirectory: true)
                .appendingPathComponent(fileName).path)
        }
        // Embedded review apps may not expose privateFrameworksPath. Keep the
        // packaged layout explicit: QaptrReview.app/Contents/Frameworks/<library>.
        paths.append(bundle.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Frameworks", isDirectory: true)
            .appendingPathComponent(fileName).path)
        if let executableDirectory = bundle.executableURL?.deletingLastPathComponent() {
            paths.append(executableDirectory.appendingPathComponent(fileName).path)
        }
        paths.append(fileName)
        return paths.reduce(into: []) { uniquePaths, path in
            if !uniquePaths.contains(path) {
                uniquePaths.append(path)
            }
        }
    }
}

/// A loaded handle onto the native review-ffi library's exported symbols.
private final class ReviewFFILibrary: @unchecked Sendable {
    let handle: UnsafeMutableRawPointer
    let storeOpen: StoreOpenFunction
    let storeDestroy: StoreDestroyFunction
    let storeSnapshot: StoreSnapshotFunction
    let storeLastError: StoreLastErrorFunction
    let reviewStatus: ReviewStatusFunction
    let providerReadiness: ProviderReadinessFunction
    let observationDetail: DocumentBridgeFunction
    let workflowGenerate: DocumentBridgeFunction
    let workflowExport: DocumentBridgeFunction
    let keyBootstrap: KeyBootstrapFunction
    let permissionState: PermissionStateFunction
    let permissionRequest: PermissionRequestFunction
    let loginItemStatus: LoginItemStatusFunction
    let loginItemSetEnabled: LoginItemSetEnabledFunction

    init() throws {
        let candidates = ReviewFFILibraryPath.candidates(
            environment: ProcessInfo.processInfo.environment,
            bundle: .main
        )
        var handle: UnsafeMutableRawPointer?
        for path in candidates {
            if let loaded = dlopen(path, RTLD_NOW | RTLD_LOCAL) {
                handle = loaded
                break
            }
        }
        guard let handle else { throw ReviewBridgeError.libraryUnavailable }
        self.handle = handle
        do {
            self.storeOpen = try Self.load("qaptr_store_open", from: handle)
            self.storeDestroy = try Self.load("qaptr_store_destroy", from: handle)
            self.storeSnapshot = try Self.load("qaptr_store_snapshot_json", from: handle)
            self.storeLastError = try Self.load("qaptr_store_last_error", from: handle)
            self.reviewStatus = try Self.load("qaptr_review_status_json", from: handle)
            self.providerReadiness = try Self.load("qaptr_provider_readiness_json", from: handle)
            self.observationDetail = try Self.load("qaptr_observation_detail_json", from: handle)
            self.workflowGenerate = try Self.load("qaptr_workflow_generate_json", from: handle)
            self.workflowExport = try Self.load("qaptr_workflow_export_json", from: handle)
            self.keyBootstrap = try Self.load("qaptr_key_bootstrap_json", from: handle)
            self.permissionState = try Self.load("qaptr_permission_state", from: handle)
            self.permissionRequest = try Self.load("qaptr_permission_request", from: handle)
            self.loginItemStatus = try Self.load("qaptr_login_item_status", from: handle)
            self.loginItemSetEnabled = try Self.load("qaptr_login_item_set_enabled", from: handle)
        } catch {
            dlclose(handle)
            throw error
        }
    }

    deinit {
        dlclose(handle)
    }

    private static func load<Function>(_ name: String, from handle: UnsafeMutableRawPointer) throws -> Function {
        guard let symbol = dlsym(handle, name) else {
            throw ReviewBridgeError.symbolMissing(name)
        }
        return unsafeBitCast(symbol, to: Function.self)
    }
}

/// The permission codes shared with `crates/qaptr-review-ffi/src/system.rs`.
public enum BridgePermission: Int32 {
    case screenCapture = 0
    case accessibilityContext = 1
}

/// The native durable-history and system-status bridge used by the review app.
public final class ReviewBridge: @unchecked Sendable {
    private let library: ReviewFFILibrary
    private let storeHandle: UnsafeMutableRawPointer
    private let bundleIdentifier: Data

    public init(
        storePath: URL,
        bundleIdentifier: String,
        vaultPath: URL? = nil,
        generationID: String = "generation-1"
    ) throws {
        let library = try ReviewFFILibrary()
        try Self.bootstrap(
            library: library,
            vaultPath: vaultPath ?? Self.defaultVaultPath(for: storePath),
            generationID: generationID
        )
        let pathData = Data(storePath.path.utf8)
        let handle: UnsafeMutableRawPointer? = pathData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            return library.storeOpen(UnsafeRawPointer(baseAddress), pathData.count)
        }
        guard let handle else {
            throw ReviewBridgeError.storeUnavailable
        }
        self.library = library
        self.storeHandle = handle
        self.bundleIdentifier = Data(bundleIdentifier.utf8)
    }

    static func defaultVaultPath(for storePath: URL) -> URL {
        storePath.deletingLastPathComponent().appendingPathComponent("vault", isDirectory: true)
    }

    private static func bootstrap(
        library: ReviewFFILibrary,
        vaultPath: URL,
        generationID: String
    ) throws {
        let vaultData = Data(vaultPath.path.utf8)
        let generationData = Data(generationID.utf8)
        var capacity = 256
        while true {
            var buffer = [UInt8](repeating: 0, count: capacity)
            let required = vaultData.withUnsafeBytes { vaultBytes in
                generationData.withUnsafeBytes { generationBytes in
                    buffer.withUnsafeMutableBytes { outputBytes in
                        library.keyBootstrap(
                            vaultBytes.baseAddress,
                            vaultData.count,
                            generationBytes.baseAddress,
                            generationData.count,
                            outputBytes.baseAddress,
                            capacity
                        )
                    }
                }
            }
            guard required > 0 else {
                throw ReviewBridgeError.secureBootstrapUnavailable("native bootstrap returned no result")
            }
            guard required <= capacity else {
                capacity = required
                continue
            }
            let data = Data(buffer.prefix(required - 1))
            guard
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let ready = root["ready"] as? Bool
            else {
                throw ReviewBridgeError.secureBootstrapUnavailable("native bootstrap returned invalid JSON")
            }
            guard ready else {
                let reason = root["reason"] as? String ?? "unknown bootstrap failure"
                throw ReviewBridgeError.secureBootstrapUnavailable(reason)
            }
            return
        }
    }

    deinit {
        library.storeDestroy(storeHandle)
    }

    /// Reads the current durable-history snapshot.
    public func snapshot() throws -> ReviewSnapshot {
        var capacity = 4_096
        while true {
            var buffer = [UInt8](repeating: 0, count: capacity)
            let required = buffer.withUnsafeMutableBytes { bytes in
                library.storeSnapshot(storeHandle, bytes.baseAddress, capacity)
            }
            if required == 0 {
                throw ReviewBridgeError.snapshotUnavailable(lastStoreError())
            }
            if required <= capacity {
                let data = Data(buffer.prefix(required - 1))
                do {
                    return try ReviewSnapshotDecoder.decode(data)
                } catch {
                    throw ReviewBridgeError.snapshotUnavailable(String(describing: error))
                }
            }
            capacity = required
        }
    }

    /// Reads a compact review status: durable-history availability and
    /// counts, plus live-analysis availability. This never reports a live
    /// capture session or provider result; use `snapshot()` for durable
    /// content.
    public func reviewStatus() throws -> ReviewStatus {
        var capacity = 1_024
        while true {
            var buffer = [UInt8](repeating: 0, count: capacity)
            let required = buffer.withUnsafeMutableBytes { bytes in
                library.reviewStatus(storeHandle, bytes.baseAddress, capacity)
            }
            if required == 0 {
                throw ReviewBridgeError.snapshotUnavailable(lastStoreError())
            }
            if required <= capacity {
                let data = Data(buffer.prefix(required - 1))
                do {
                    return try ReviewStatusDecoder.decode(data)
                } catch {
                    throw ReviewBridgeError.snapshotUnavailable(String(describing: error))
                }
            }
            capacity = required
        }
    }

    /// Reads the bounded, path-only readiness state of the supported local
    /// CLI providers. An installed executable is never treated as usable.
    public func providerReadinessSnapshot() throws -> ProviderReadinessSnapshot {
        let maximumCapacity = 4_096
        var capacity = 512
        while true {
            var buffer = [UInt8](repeating: 0, count: capacity)
            let required = buffer.withUnsafeMutableBytes { bytes in
                library.providerReadiness(bytes.baseAddress, capacity)
            }
            guard required > 0 else {
                throw ReviewBridgeError.providerReadinessUnavailable("native readiness returned no result")
            }
            guard required <= maximumCapacity else {
                throw ReviewBridgeError.providerReadinessUnavailable("native readiness exceeded its output limit")
            }
            if required <= capacity {
                let data = Data(buffer.prefix(required - 1))
                do {
                    return try ProviderReadinessDecoder.decode(data)
                } catch {
                    throw ReviewBridgeError.providerReadinessUnavailable(String(describing: error))
                }
            }
            capacity = required
        }
    }

    private func lastStoreError() -> String {
        var output = [UInt8](repeating: 0, count: 512)
        let capacity = output.count
        let required = output.withUnsafeMutableBytes { bytes in
            library.storeLastError(storeHandle, bytes.baseAddress, capacity)
        }
        guard required > 0 else { return "unknown store error" }
        return String(decoding: output.prefix(min(required - 1, output.count)), as: UTF8.self)
    }

    /// Fetches durable scalar detail for one observation. This never opens
    /// the source vault bundle: `observationID` is the same stable scalar
    /// identifier already visible in `snapshot()`, and the response is the
    /// same bounded observation fields returned there.
    public func observationDetail(observationID: String) throws -> QaptrObservation {
        let request: [String: Any] = ["version": 1, "observation_id": observationID]
        let object = try runDocumentOperation(library.observationDetail, request: request)
        guard let fields = object["observation"] as? [String: Any] else {
            throw ReviewBridgeError.documentOperationFailed("response missing \"observation\"")
        }
        do {
            return try ReviewSnapshotDecoder.decodeObservation(fields)
        } catch {
            throw ReviewBridgeError.documentOperationFailed(String(describing: error))
        }
    }

    /// Generates (or regenerates, replacing the same stable row) the
    /// canonical workflow for one durable observation, using only
    /// already-observed scalar material. Missing sequence detail stays
    /// visibly missing; nothing is inferred.
    public func generateWorkflow(observationID: String) throws -> WorkflowSummary {
        let request: [String: Any] = ["version": 1, "observation_id": observationID]
        let object = try runDocumentOperation(library.workflowGenerate, request: request)
        guard let fields = object["workflow"] as? [String: Any] else {
            throw ReviewBridgeError.documentOperationFailed("response missing \"workflow\"")
        }
        do {
            return try ReviewSnapshotDecoder.decodeWorkflow(fields)
        } catch {
            throw ReviewBridgeError.documentOperationFailed(String(describing: error))
        }
    }

    /// Saves one canonical Markdown export variant to a caller-chosen
    /// destination, such as a path already chosen through a native save
    /// panel. This bridge never picks a developer path, creates parent
    /// directories, or launches another app, agent, or automation.
    public func exportWorkflow(
        workflowID: String,
        variant: MarkdownExportVariant,
        destination: URL
    ) throws {
        let request: [String: Any] = [
            "version": 1,
            "workflow_id": workflowID,
            "variant": variant.wireValue,
            "destination": destination.path,
        ]
        _ = try runDocumentOperation(library.workflowExport, request: request)
    }

    /// Executes one bounded document-bridge request (observation detail,
    /// workflow generation, or export) and returns its decoded JSON object,
    /// or throws a typed error for a terse `ok:false` result or malformed
    /// output. Shared by all three so each caller only handles its own
    /// payload shape.
    private func runDocumentOperation(
        _ function: DocumentBridgeFunction,
        request: [String: Any]
    ) throws -> [String: Any] {
        let requestData = try JSONSerialization.data(withJSONObject: request)
        var capacity = 1_024
        let maximumCapacity = 8_192
        while true {
            var buffer = [UInt8](repeating: 0, count: capacity)
            let required = requestData.withUnsafeBytes { requestBytes in
                buffer.withUnsafeMutableBytes { outputBytes in
                    function(
                        storeHandle,
                        requestBytes.baseAddress,
                        requestData.count,
                        outputBytes.baseAddress,
                        capacity
                    )
                }
            }
            guard required > 0 else {
                throw ReviewBridgeError.documentOperationFailed("native call returned no result")
            }
            guard required <= maximumCapacity else {
                throw ReviewBridgeError.documentOperationFailed("native call exceeded its output limit")
            }
            if required <= capacity {
                let data = Data(buffer.prefix(required - 1))
                let object: [String: Any]
                do {
                    guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw ReviewBridgeError.documentOperationFailed("response is not a JSON object")
                    }
                    object = parsed
                } catch {
                    throw ReviewBridgeError.documentOperationFailed(String(describing: error))
                }
                guard object["ok"] as? Bool == true else {
                    let reason = object["error"] as? String ?? "unknown document operation failure"
                    throw ReviewBridgeError.documentOperationFailed(reason)
                }
                return object
            }
            capacity = required
        }
    }

    /// Reads a permission's state without prompting.
    public func permissionState(_ permission: BridgePermission) -> PermissionStatus {
        let code = bundleIdentifier.withUnsafeBytes { bytes in
            library.permissionState(bytes.baseAddress, bundleIdentifier.count, permission.rawValue)
        }
        return PermissionStatus(bridgeCode: code)
    }

    /// Requests a permission through the native prompt, then reports its state.
    public func requestPermission(_ permission: BridgePermission) -> PermissionStatus {
        let code = bundleIdentifier.withUnsafeBytes { bytes in
            library.permissionRequest(bytes.baseAddress, bundleIdentifier.count, permission.rawValue)
        }
        return PermissionStatus(bridgeCode: code)
    }

    /// Reads whether Qaptr is registered to start at login.
    public func loginItemEnabled() -> Bool {
        library.loginItemStatus() == 1
    }

    /// Sets login-item registration and returns the state confirmed by the OS.
    @discardableResult
    public func setLoginItemEnabled(_ enabled: Bool) -> Bool {
        library.loginItemSetEnabled(enabled ? 1 : 0) == 1
    }
}
