import Darwin
import Foundation
import QaptrHelperCore

private typealias CreateFunction = @convention(c) (UnsafeRawPointer?, Int) -> UnsafeMutableRawPointer?
private typealias DestroyFunction = @convention(c) (UnsafeMutableRawPointer) -> Void
private typealias PublicKeyFunction = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeRawPointer?,
    Int,
    UnsafeMutableRawPointer?,
    Int
) -> Int
private typealias SealFunction = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeRawPointer?,
    Int,
    Int64,
    UnsafeRawPointer?,
    Int,
    UnsafeRawPointer?,
    Int,
    UnsafeRawPointer?,
    Int,
    UnsafeRawPointer?,
    Int
) -> Int32
private typealias LastErrorFunction = @convention(c) (
    UnsafeMutableRawPointer,
    UnsafeMutableRawPointer?,
    Int
) -> Int

private final class RustVaultAPI: @unchecked Sendable {
    let library: UnsafeMutableRawPointer
    let create: CreateFunction
    let destroy: DestroyFunction
    let publicKey: PublicKeyFunction
    let seal: SealFunction
    let lastError: LastErrorFunction

    init() throws {
        let path = ProcessInfo.processInfo.environment["QAPTR_FFI_LIBRARY_PATH"]
            ?? Bundle.main.privateFrameworksPath.map { "\($0)/libqaptr_ffi.dylib" }
            ?? "libqaptr_ffi.dylib"
        guard let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw VaultBridgeError.creationFailed
        }
        self.library = library
        do {
            self.create = try Self.load("qaptr_vault_create", from: library)
            self.destroy = try Self.load("qaptr_vault_destroy", from: library)
            self.publicKey = try Self.load("qaptr_vault_public_key", from: library)
            self.seal = try Self.load("qaptr_vault_seal", from: library)
            self.lastError = try Self.load("qaptr_vault_last_error", from: library)
        } catch {
            dlclose(library)
            throw error
        }
    }

    deinit {
        dlclose(library)
    }

    private static func load<Function>(_ name: String, from library: UnsafeMutableRawPointer) throws -> Function {
        guard let symbol = dlsym(library, name) else {
            throw VaultBridgeError.creationFailed
        }
        return unsafeBitCast(symbol, to: Function.self)
    }
}

final class RustVaultSealer: BundleSealer, @unchecked Sendable {
    private let api: RustVaultAPI
    private let handle: UnsafeMutableRawPointer
    private let generationID: Data
    private let publicKey: Data

    init(root: URL, generationID: String) throws {
        let api = try RustVaultAPI()
        let rootData = Data(root.path.utf8)
        let generationData = Data(generationID.utf8)
        let handle: UnsafeMutableRawPointer? = rootData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            return api.create(UnsafeRawPointer(baseAddress), rootData.count)
        }
        guard let handle else {
            throw VaultBridgeError.creationFailed
        }
        self.api = api
        self.handle = handle
        self.generationID = generationData
        do {
            self.publicKey = try Self.readPublicKey(api: api, handle: handle, generation: generationData)
        } catch {
            api.destroy(handle)
            throw error
        }
    }

    deinit {
        api.destroy(handle)
    }

    func seal(
        captureID: String,
        capturedAtMillis: Int64,
        frame: CapturedFrame,
        context: SampledContext
    ) throws {
        let captureData = Data(captureID.utf8)
        let contextData = try context.encoded()
        let result = captureData.withUnsafeBytes { captureBytes in
            generationID.withUnsafeBytes { generationBytes in
                publicKey.withUnsafeBytes { publicBytes in
                    frame.imageData.withUnsafeBytes { imageBytes in
                        contextData.withUnsafeBytes { contextBytes in
                            guard
                                let captureAddress = captureBytes.bindMemory(to: UInt8.self).baseAddress,
                                let generationAddress = generationBytes.bindMemory(to: UInt8.self).baseAddress,
                                let publicAddress = publicBytes.bindMemory(to: UInt8.self).baseAddress,
                                let imageAddress = imageBytes.bindMemory(to: UInt8.self).baseAddress,
                                let contextAddress = contextBytes.bindMemory(to: UInt8.self).baseAddress
                            else {
                                return Int32(-1)
                            }
                            return api.seal(
                                handle,
                                UnsafeRawPointer(captureAddress),
                                captureData.count,
                                capturedAtMillis,
                                UnsafeRawPointer(generationAddress),
                                generationID.count,
                                UnsafeRawPointer(publicAddress),
                                publicKey.count,
                                UnsafeRawPointer(imageAddress),
                                frame.imageData.count,
                                UnsafeRawPointer(contextAddress),
                                contextData.count
                            )
                        }
                    }
                }
            }
        }
        guard result == 0 else {
            throw VaultBridgeError.sealingFailed(Self.lastError(api: api, handle: handle))
        }
    }

    private static func readPublicKey(
        api: RustVaultAPI,
        handle: UnsafeMutableRawPointer,
        generation: Data
    ) throws -> Data {
        var output = [UInt8](repeating: 0, count: 256)
        let outputCapacity = output.count
        let required = generation.withUnsafeBytes { bytes in
            guard let address = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return output.withUnsafeMutableBytes { outputBytes in
                api.publicKey(handle, UnsafeRawPointer(address), generation.count, outputBytes.baseAddress, outputCapacity)
            }
        }
        guard required > 0, required <= output.count else {
            throw VaultBridgeError.publicKeyUnavailable(lastError(api: api, handle: handle))
        }
        return Data(output.prefix(required - 1))
    }

    private static func lastError(api: RustVaultAPI, handle: UnsafeMutableRawPointer) -> String {
        var output = [UInt8](repeating: 0, count: 512)
        let outputCapacity = output.count
        let required = output.withUnsafeMutableBytes { bytes in
            api.lastError(handle, bytes.baseAddress, outputCapacity)
        }
        guard required > 0 else {
            return "unknown vault error"
        }
        return String(decoding: output.prefix(min(required - 1, output.count)), as: UTF8.self)
    }
}

private enum VaultBridgeError: Error, CustomStringConvertible {
    case creationFailed
    case publicKeyUnavailable(String)
    case sealingFailed(String)

    var description: String {
        switch self {
        case .creationFailed:
            "vault bridge could not be loaded"
        case let .publicKeyUnavailable(message):
            "generation public key unavailable: \(message)"
        case let .sealingFailed(message):
            "capture sealing failed: \(message)"
        }
    }
}
