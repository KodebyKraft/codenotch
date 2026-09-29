import Foundation

/// The Higgsfield credit balance, as the CLI reports it. See `HiggsfieldCLI`
/// for why the CLI is asked rather than its token read, and `HiggsfieldUsage`
/// for why this is a count and not a ring.
actor HiggsfieldProvider: UsageProvider {
    nonisolated let id = "higgsfield"
    nonisolated let displayName = "Higgsfield"
    nonisolated let glyph = ProviderGlyph.higgsfield

    /// Injected CLI answer for tests. Nil in production: the binary is located
    /// at fetch time, so installing the CLI without a relaunch still works.
    nonisolated private let cli: (@Sendable () throws -> HiggsfieldCLI.Output)?
    nonisolated private let locateBinary: @Sendable () -> URL?

    nonisolated(unsafe) private var lastKnownEmail: String?
    nonisolated(unsafe) private var lastKnownPlan: String?

    init(cli: (@Sendable () throws -> HiggsfieldCLI.Output)? = nil,
         locateBinary: @escaping @Sendable () -> URL? = { HiggsfieldCLI.locateBinary() }) {
        self.cli = cli
        self.locateBinary = locateBinary
    }

    /// A Mac without the CLI should not grow a sign-in ring for it.
    nonisolated var isVisibleWhenAbsent: Bool { locateBinary() != nil }

    nonisolated var signInRoute: SignInRoute {
        .command("higgsfield auth login", name: "Higgsfield",
                 install: URL(string: "https://www.npmjs.com/package/@higgsfield/cli"))
    }

    nonisolated func account() -> ProviderAccount? {
        guard locateBinary() != nil else { return nil }
        return ProviderAccount(label: lastKnownEmail, plan: lastKnownPlan,
                               source: L10n.t("Higgsfield CLI"),
                               manageURL: URL(string: "https://higgsfield.ai/pricing"))
    }

    /// The login is the CLI's to end, not ours.
    nonisolated func signOut() async {}

    /// Nothing is cached: the CLI is asked on every fetch.
    nonisolated func forgetCachedCredential() {}

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let output: HiggsfieldCLI.Output
        if let cli {
            output = try cli()
        } else {
            guard let binary = locateBinary() else { throw UsageProviderError.needsAuth }
            output = try HiggsfieldCLI.run(binary: binary)
        }
        let reading = try HiggsfieldUsage.reading(from: output)
        lastKnownEmail = reading.email
        lastKnownPlan = reading.plan
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                fidelity: .official, status: .ok, windows: reading.windows,
                                headlineID: HiggsfieldUsage.headlineID,
                                plan: reading.plan)
    }
}
