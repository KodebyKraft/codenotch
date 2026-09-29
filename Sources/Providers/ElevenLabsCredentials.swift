import Foundation

/// Everywhere an ElevenLabs key can come from, as closures so a test can
/// stand each one in without a keychain.
struct ElevenLabsCredentialSources {
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var settingsKey: () -> String? = ElevenLabsCredentials.cachedSettingsKey
    var settingsPresent: () -> Bool = ElevenLabsCredentials.isSettingsKeyPresent
    var deleteSettingsKey: () -> Void = ElevenLabsCredentials.deleteSettingsKey
    var forgetCached: () -> Void = ElevenLabsCredentials.forgetCached
}

/// The ElevenLabs API key.
///
/// ElevenLabs has no CLI login to borrow, so there are only two places:
///
/// 1. `ELEVENLABS_API_KEY` in the environment — the name the official SDKs
///    read. Finder does not pass a shell's exports on, so this mostly matters
///    when Codenotch is launched from a terminal.
/// 2. A key pasted in Settings, filed in the login keychain under a service
///    name no other app uses. Codenotch owns this one, so switching the
///    provider off deletes it.
enum ElevenLabsCredentials {
    static let environmentKey = "ELEVENLABS_API_KEY"
    static let keychainService = "elevenlabs-api-key"
    static let keychainAccount = "codenotch"

    struct Credential: Equatable {
        enum Source: Equatable { case environment, settings }
        let key: String
        let source: Source
    }

    static func load(_ sources: ElevenLabsCredentialSources = ElevenLabsCredentialSources()) throws -> Credential {
        if let key = nonEmpty(sources.environment[environmentKey]) {
            return Credential(key: key, source: .environment)
        }
        if let key = nonEmpty(sources.settingsKey()) {
            return Credential(key: key, source: .settings)
        }
        throw UsageProviderError.needsAuth
    }

    /// A key names no account on its own, so there is no label to print —
    /// only that there is something to read.
    static func account(plan: String?,
                        _ sources: ElevenLabsCredentialSources = ElevenLabsCredentialSources()) -> ProviderAccount? {
        guard nonEmpty(sources.environment[environmentKey]) != nil || sources.settingsPresent() else { return nil }
        return ProviderAccount(label: nil, plan: plan, source: "ElevenLabs",
                               manageURL: URL(string: "https://elevenlabs.io/app/subscription"))
    }

    // MARK: - The key Codenotch holds itself

    /// Held until the item moves: usage polling reaches this every minute and
    /// a stored key never expires on its own.
    private static let settingsCache = CredentialCache<String> { _ in false }

    static func cachedSettingsKey() -> String? {
        try? settingsCache.value(
            itemModifiedAt: { KeychainItem.modifiedAt(service: keychainService, account: keychainAccount) },
            reload: {
                guard let key = KeychainItem.read(service: keychainService, account: keychainAccount) else {
                    throw UsageProviderError.needsAuth
                }
                return key
            }
        )
    }

    /// Attributes only, never the cache: a `store` or `delete` that just
    /// happened has to show at once.
    static func isSettingsKeyPresent() -> Bool {
        KeychainItem.modifiedAt(service: keychainService, account: keychainAccount) != nil
    }

    static func storeSettingsKey(_ key: String) {
        guard let trimmed = nonEmpty(key) else { return }
        settingsCache.forget()
        _ = KeychainItem.store(service: keychainService, account: keychainAccount, value: trimmed)
    }

    static func deleteSettingsKey() {
        settingsCache.forget()
        KeychainItem.delete(service: keychainService, account: keychainAccount)
    }

    static func forgetCached() { settingsCache.forget() }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
