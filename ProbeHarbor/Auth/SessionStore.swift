import Foundation
import Security

/// Same contract as the Android app and web dashboard: the site validates
/// `sb-access-token` + `sb-refresh-token` cookies. `mfaSatisfied` maps to
/// `sb-mfa-required=0`, which YubiKey OTP needs because its AAL stays aal1.
struct SessionTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var mfaSatisfied: Bool
}

protocol SessionStoring: AnyObject, Sendable {
    func load() -> SessionTokens?
    func save(_ tokens: SessionTokens)
    func clear()
}

/// Session tokens in the Keychain, readable after first unlock so background
/// push handling (Acknowledge) can call the API.
final class KeychainSessionStore: SessionStoring, @unchecked Sendable {
    private let service = "dev.probeharbor.ios.session"
    private let account = "tokens"
    private let lock = NSLock()
    private var cached: SessionTokens??

    func load() -> SessionTokens? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let tokens = try? JSONDecoder().decode(SessionTokens.self, from: data)
        else {
            cached = .some(nil)
            return nil
        }
        cached = .some(tokens)
        return tokens
    }

    func save(_ tokens: SessionTokens) {
        lock.lock(); defer { lock.unlock() }
        cached = .some(tokens)
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(base as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(base.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        cached = .some(nil)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory store for tests and previews.
final class MemorySessionStore: SessionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: SessionTokens?
    init(_ tokens: SessionTokens? = nil) { self.tokens = tokens }
    func load() -> SessionTokens? { lock.lock(); defer { lock.unlock() }; return tokens }
    func save(_ tokens: SessionTokens) { lock.lock(); self.tokens = tokens; lock.unlock() }
    func clear() { lock.lock(); tokens = nil; lock.unlock() }
}
