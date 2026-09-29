import Foundation

/// This billing period's credits against the plan's allowance — the bar on
/// ElevenLabs' Subscription page — read from the endpoint that page draws it
/// from. See `ElevenLabsUsage` for the shape and `ElevenLabsCredentials` for
/// where the key comes from.
///
/// The numbers are ElevenLabs' own, so this is `.official`.
actor ElevenLabsProvider: UsageProvider {
    nonisolated let id = "elevenlabs"
    nonisolated let displayName = "ElevenLabs"
    nonisolated let glyph = ProviderGlyph.elevenlabs

    private let session: URLSession
    private let archive: UsageArchive
    nonisolated private let sources: ElevenLabsCredentialSources
    private let now: @Sendable () -> Date
    private var retryNoEarlierThan: Date?

    /// The tier the last reading named, for the settings row. The key itself
    /// says nothing about the plan.
    nonisolated(unsafe) private var lastKnownPlan: String?

    init(session: URLSession = .shared, archive: UsageArchive = UsageArchive(),
         sources: ElevenLabsCredentialSources = ElevenLabsCredentialSources(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.archive = archive
        self.sources = sources
        self.now = now
        retryNoEarlierThan = archive.loadBackoffUntil(providerID: "elevenlabs")
    }

    nonisolated var signInRoute: SignInRoute {
        .guidance(L10n.t("Paste an ElevenLabs API key below, or export ELEVENLABS_API_KEY."))
    }

    nonisolated func account() -> ProviderAccount? {
        ElevenLabsCredentials.account(plan: lastKnownPlan, sources)
    }

    /// The pasted key is Codenotch's own, so signing out deletes it.
    nonisolated func signOut() async { sources.deleteSettingsKey() }

    nonisolated func forgetCachedCredential() { sources.forgetCached() }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        if let retryNoEarlierThan, retryNoEarlierThan > now() {
            throw UsageProviderError.rateLimited(retryAfter: retryNoEarlierThan.timeIntervalSince(now()))
        }
        let credential = try ElevenLabsCredentials.load(sources)

        var request = URLRequest(url: ElevenLabsUsage.endpoint)
        request.setValue(credential.key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw UsageProviderError.timedOut
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UsageProviderError.apiError(L10n.t("Couldn't reach ElevenLabs. Check your connection."))
        }

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401 {
            // A key restricted to other endpoints is refused here with a 401
            // too, but it is a valid key: asking for a new one would be wrong
            // advice, so the permission case is named separately.
            if Self.isMissingPermission(data) {
                throw UsageProviderError.apiError(
                    L10n.t("This ElevenLabs key cannot read the subscription — enable User read access for it")
                )
            }
            sources.forgetCached()
            throw UsageProviderError.needsAuth
        }
        if status == 429 {
            let delay = max(60, Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60)
            retryNoEarlierThan = now().addingTimeInterval(delay)
            archive.saveBackoffUntil(retryNoEarlierThan, providerID: id)
            throw UsageProviderError.rateLimited(retryAfter: delay)
        }
        guard (200..<300).contains(status) else { throw UsageProviderError.badResponse(status: status) }

        let reading = try ElevenLabsUsage.reading(from: data)
        lastKnownPlan = reading.plan
        retryNoEarlierThan = nil
        archive.saveBackoffUntil(nil, providerID: id)
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                fidelity: .official, status: .ok, windows: reading.windows,
                                headlineID: ElevenLabsUsage.headlineID,
                                plan: reading.plan)
    }

    /// `{"detail": {"status": "missing_permissions", …}}` — how ElevenLabs
    /// says a scoped key lacks `user_read`.
    static func isMissingPermission(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = root["detail"] as? [String: Any]
        else { return false }
        return detail["status"] as? String == "missing_permissions"
    }
}
