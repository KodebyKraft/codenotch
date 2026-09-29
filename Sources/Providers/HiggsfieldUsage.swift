import Foundation

/// Parses what `higgsfield account status --json` prints:
///
/// ```json
/// { "credits": 1038.15, "email": "…", "subscription_plan_type": "ultimate" }
/// ```
///
/// A balance and nothing to divide it by: the CLI does not say what the plan
/// grants, so there is no share to draw and the window is a count row, not a
/// ring made up from a guessed allowance.
enum HiggsfieldUsage {
    static let headlineID = "credits"

    struct Reading: Equatable {
        let windows: [LimitWindow]
        let email: String?
        let plan: String?
    }

    static func reading(from output: HiggsfieldCLI.Output) throws -> Reading {
        guard output.status == 0 else { throw failure(output) }
        guard let root = try? JSONSerialization.jsonObject(with: Data(output.stdout.utf8)) as? [String: Any],
              let credits = (root["credits"] as? NSNumber)?.doubleValue,
              credits.isFinite
        else { throw UsageProviderError.badResponse(status: 0) }

        let left = count(credits)
        return Reading(
            windows: [LimitWindow(
                id: headlineID,
                label: L10n.t("Credits"),
                usedText: left,
                detail: L10n.t("\(left) credits left")
            )],
            email: (root["email"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            plan: (root["subscription_plan_type"] as? String)
                .flatMap { $0.isEmpty ? nil : $0.split(separator: "_").map { $0.capitalized }.joined(separator: " ") }
        )
    }

    /// The CLI explains itself in an `Error:` line and a `Hint:` line naming
    /// the command that fixes it; the hint decides which status this is.
    static func failure(_ output: HiggsfieldCLI.Output) -> UsageProviderError {
        let said = output.stderr + "\n" + output.stdout
        if said.contains("auth login") { return .needsAuth }
        if said.contains("workspace set") {
            return .apiError(L10n.t("No Higgsfield workspace selected — run higgsfield workspace set in Terminal"))
        }
        let line = said.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("Error:") }
            .map { String($0.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces) }
        return .apiError(line ?? L10n.t("higgsfield exited with status \(Int(output.status))"))
    }

    /// "1,038", whatever the Mac's region puts between the thousands. Whole
    /// credits: the fractions come from per-second video pricing and are
    /// noise at a glance.
    static func count(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .down
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }
}
