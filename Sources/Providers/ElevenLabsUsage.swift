import Foundation

/// Parses `GET https://api.elevenlabs.io/v1/user/subscription` — the endpoint
/// behind the Subscription page's credit bar:
///
/// ```json
/// { "tier": "starter", "character_count": 3659, "character_limit": 40000,
///   "next_character_count_reset_unix": 1793097107,
///   "character_refresh_period": "monthly_period", … }
/// ```
///
/// The field names still say "character" although the dashboard now calls the
/// same numbers credits; the dashboard's word is the one printed.
enum ElevenLabsUsage {
    static let endpoint = URL(string: "https://api.elevenlabs.io/v1/user/subscription")!
    static let headlineID = "credits"

    struct Reading: Equatable {
        let windows: [LimitWindow]
        let plan: String?
    }

    static func reading(from data: Data) throws -> Reading {
        // A string where a count should be, or a negative count, is the shape
        // changing under us — "HTTP 0" beats a ring drawn from a guess.
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let used = (root["character_count"] as? NSNumber)?.doubleValue,
              used.isFinite, used >= 0
        else { throw UsageProviderError.badResponse(status: 0) }

        let resetsAt = (root["next_character_count_reset_unix"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue) }
        let duration: TimeInterval? = switch root["character_refresh_period"] as? String {
        case "monthly_period": 30 * 86400
        case "annual_period": 365 * 86400
        default: nil
        }
        let plan = (root["tier"] as? String).flatMap { $0.isEmpty ? nil : planName($0) }

        let limit = (root["character_limit"] as? NSNumber)?.doubleValue
        guard let limit, limit.isFinite, limit > 0 else {
            // No allowance means no share of one — a count row, not a 0% ring.
            return Reading(windows: [LimitWindow(
                id: headlineID,
                label: L10n.t("Credits"),
                usedText: count(used),
                detail: L10n.t("\(count(used)) credits used"),
                resetsAt: resetsAt,
                duration: duration
            )], plan: plan)
        }

        // Not clamped at 1: usage-based billing lets an account run past its
        // allowance, and what ElevenLabs reports past it is still the number.
        return Reading(windows: [LimitWindow(
            id: headlineID,
            label: L10n.t("Credits"),
            usedFraction: used / limit,
            usedText: count(used),
            detail: L10n.t("\(count(used)) of \(count(limit))"),
            resetsAt: resetsAt,
            duration: duration
        )], plan: plan)
    }

    /// "40,000", whatever the Mac's region puts between the thousands.
    static func count(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }

    /// Tier ids are snake case — `starter`, `creator`, `pro`, `growing_business`.
    static func planName(_ tier: String) -> String {
        tier.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}
