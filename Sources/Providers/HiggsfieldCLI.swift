import Foundation

/// Higgsfield's own `account status`, asked of the CLI rather than of any
/// credential this app could hold.
///
/// The CLI's access token lives for a few hours and is renewed with a
/// rotating refresh token. Reading that token here would go stale between
/// runs of the CLI, and renewing it here would spend the refresh token out
/// from under the CLI and sign it out. Asking the CLI keeps the renewal where
/// it belongs.
enum HiggsfieldCLI {
    /// Long enough for a cold start and a token renewal, short enough that a
    /// wedged process cannot hold a refresh open.
    static let timeout: TimeInterval = 20

    static let arguments = ["account", "status", "--json"]

    // MARK: - Finding the binary

    /// Where `npm i -g @higgsfield/cli` links the command. Deliberately not
    /// `hf`: that name is also the Hugging Face CLI's.
    static let candidates = [
        "/opt/homebrew/bin/higgsfield",
        "/usr/local/bin/higgsfield",
        "~/.local/bin/higgsfield"
    ]

    /// Nil means the CLI is not installed anywhere it installs itself.
    ///
    /// The npm package links a Node launcher, and Finder starts this app with
    /// no Node on `PATH`, so the launcher is followed to the native binary it
    /// wraps (`../vendor/hf`) and that is what runs.
    static func locateBinary(environment: [String: String] = ProcessInfo.processInfo.environment,
                             fileManager: FileManager = .default) -> URL? {
        if let override = environment["HIGGSFIELD_CLI_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            // Named, but not there: falling through would run a different
            // binary than the one pointed at.
            return native((override as NSString).expandingTildeInPath, fileManager: fileManager)
        }
        let home = environment["HOME"] ?? NSHomeDirectory()
        let nvm = (home as NSString).appendingPathComponent(".nvm/versions/node")
        let nodeTrees = ((try? fileManager.contentsOfDirectory(atPath: nvm)) ?? [])
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { (nvm as NSString).appendingPathComponent("\($0)/bin/higgsfield") }
        let all = candidates.map { $0.replacingOccurrences(of: "~", with: home) } + nodeTrees
        return all.lazy.compactMap { native($0, fileManager: fileManager) }.first
    }

    static func native(_ path: String, fileManager: FileManager) -> URL? {
        guard path.hasPrefix("/"), fileManager.isExecutableFile(atPath: path) else { return nil }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard resolved.pathExtension == "js" else { return resolved }
        let vendored = resolved.deletingLastPathComponent()
            .appendingPathComponent("../vendor/hf").standardizedFileURL
        return fileManager.isExecutableFile(atPath: vendored.path) ? vendored : nil
    }

    // MARK: - Asking it

    struct Output: Equatable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(binary: URL, timeout: TimeInterval = timeout) throws -> Output {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        // The answer is a few hundred bytes, well under a pipe's buffer, so
        // reading after exit cannot deadlock the CLI.
        if exited.wait(timeout: .now() + timeout) != .success {
            process.terminate()
            _ = kill(process.processIdentifier, SIGKILL)
            throw UsageProviderError.timedOut
        }
        return Output(
            status: process.terminationStatus,
            stdout: String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}
