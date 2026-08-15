import Foundation
import QaptrReviewCore
import Security

struct ProviderConnectionState: Equatable {
    enum Failure: Equatable {
        case invalidKey
        case unavailable
        case unableToSave

        var message: String {
            switch self {
            case .invalidKey: "That key did not work. Check it and try again."
            case .unavailable: "Qaptr could not check the key. Try again soon."
            case .unableToSave: "Qaptr could not save this key in Keychain."
            }
        }
    }

    enum Kind: Equatable { case notConnected, needsKey, checking, connected, failed(Failure) }
    let kind: Kind

    static let notConnected = Self(kind: .notConnected)
    static let needsKey = Self(kind: .needsKey)
    static let checking = Self(kind: .checking)
    static let connected = Self(kind: .connected)

    static func failed(_ failure: Failure) -> Self { Self(kind: .failed(failure)) }

    var title: String {
        switch kind {
        case .notConnected: "Not connected"
        case .needsKey: "Add a key"
        case .checking: "Checking"
        case .connected: "Connected"
        case .failed: "Try again"
        }
    }

    var detail: String {
        if case .failed(let failure) = kind { return failure.message }
        return title
    }
}

protocol ProviderCredentialStoring {
    func containsOpenRouterKey() -> Bool
    func saveOpenRouterKey(_ key: String) throws
    func removeOpenRouterKey() throws
}

struct KeychainProviderCredentialStore: ProviderCredentialStoring {
    private let service = "com.qaptr.review.credentials"
    private let account = "openrouter.api_key"

    func containsOpenRouterKey() -> Bool {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return false }
        return !data.isEmpty
    }

    func saveOpenRouterKey(_ key: String) throws {
        let data = Data(key.utf8)
        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else { throw KeychainError.save }
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw KeychainError.save }
    }

    func removeOpenRouterKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.remove }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private enum KeychainError: Error { case save, remove }
}

protocol OpenRouterChecking: Sendable {
    func check(apiKey: String) async -> ProviderConnectionState
}

struct OpenRouterConnectionChecker: OpenRouterChecking {
    func check(apiKey: String) async -> ProviderConnectionState {
        guard let url = URL(string: "https://openrouter.ai/api/v1/auth/key") else { return .failed(.unavailable) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed(.unavailable) }
            if (200..<300).contains(http.statusCode) { return .connected }
            if http.statusCode == 401 || http.statusCode == 403 { return .failed(.invalidKey) }
            return .failed(.unavailable)
        } catch {
            return .failed(.unavailable)
        }
    }
}
