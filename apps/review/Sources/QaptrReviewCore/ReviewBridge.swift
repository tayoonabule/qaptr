import Foundation

/// Errors raised while talking to the native `qaptr-review-ffi` bridge.
public enum ReviewBridgeError: Error, CustomStringConvertible, Equatable {
    case libraryUnavailable
    case symbolMissing(String)
    case storeUnavailable
    case snapshotUnavailable(String)

    public var description: String {
        switch self {
        case .libraryUnavailable:
            "the qaptr-review-ffi library could not be loaded"
        case let .symbolMissing(name):
            "missing bridge symbol: \(name)"
        case .storeUnavailable:
            "the durable history store could not be opened"
        case let .snapshotUnavailable(reason):
            "durable history snapshot unavailable: \(reason)"
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

    public init(storePath: URL, bundleIdentifier: String) throws {
        let library = try ReviewFFILibrary()
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

    private func lastStoreError() -> String {
        var output = [UInt8](repeating: 0, count: 512)
        let capacity = output.count
        let required = output.withUnsafeMutableBytes { bytes in
            library.storeLastError(storeHandle, bytes.baseAddress, capacity)
        }
        guard required > 0 else { return "unknown store error" }
        return String(decoding: output.prefix(min(required - 1, output.count)), as: UTF8.self)
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
