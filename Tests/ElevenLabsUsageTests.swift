import XCTest
@testable import Codenotch

/// Pinned to the shape `GET /v1/user/subscription` returned for a real
/// Starter account on 29 Sep 2026. The amounts are synthetic.
final class ElevenLabsUsageTests: XCTestCase {
    private let subscription = """
    {"tier":"starter","character_count":3659,"character_limit":40000,
     "next_character_count_reset_unix":1793097107,"character_refresh_period":"monthly_period",
     "voice_limit":10,"status":"active"}
    """

    private func credits(_ json: String) throws -> LimitWindow {
        try XCTUnwrap(ElevenLabsUsage.reading(from: Data(json.utf8)).windows.first)
    }

    func testTheRingIsTheShareOfThePlanAllowance() throws {
        let credits = try credits(subscription)
        XCTAssertEqual(credits.id, ElevenLabsUsage.headlineID)
        XCTAssertEqual(credits.usedFraction ?? -1, 3659.0 / 40000, accuracy: 0.0001)
        XCTAssertEqual(credits.detail, "3,659 of 40,000")
        XCTAssertEqual(credits.resetsAt, Date(timeIntervalSince1970: 1793097107))
        XCTAssertEqual(try ElevenLabsUsage.reading(from: Data(subscription.utf8)).windows.count, 1)
    }

    func testThePlanIsNamedTheWayTheDashboardNamesIt() throws {
        XCTAssertEqual(try ElevenLabsUsage.reading(from: Data(subscription.utf8)).plan, "Starter")
        XCTAssertEqual(ElevenLabsUsage.planName("growing_business"), "Growing Business")
    }

    func testRunningPastTheAllowanceIsReportedAsPastIt() throws {
        let over = subscription.replacingOccurrences(of: #""character_count":3659"#,
                                                     with: #""character_count":44000"#)
        XCTAssertEqual(try credits(over).usedFraction ?? -1, 1.1, accuracy: 0.0001)
    }

    func testWithoutAnAllowanceThereIsNoDenominator() throws {
        let unlimited = subscription.replacingOccurrences(of: #""character_limit":40000"#,
                                                          with: #""character_limit":0"#)
        let credits = try credits(unlimited)
        XCTAssertNil(credits.usedFraction, "no allowance means no share of it, not 0%")
        XCTAssertEqual(credits.detail, "3,659 credits used")
    }

    func testAChangedShapeIsNotReadAsANumber() {
        for json in [#"{"character_count":"3659","character_limit":40000}"#,
                     #"{"character_count":-1,"character_limit":40000}"#,
                     #"{"detail":"nope"}"#] {
            XCTAssertThrowsError(try ElevenLabsUsage.reading(from: Data(json.utf8)))
        }
    }

    func testAScopedKeyIsToldApartFromABadOne() {
        let scoped = #"{"detail":{"status":"missing_permissions","message":"The API key you used is missing the permission user_read"}}"#
        XCTAssertTrue(ElevenLabsProvider.isMissingPermission(Data(scoped.utf8)))
        let invalid = #"{"detail":{"status":"invalid_api_key","message":"Invalid API key"}}"#
        XCTAssertFalse(ElevenLabsProvider.isMissingPermission(Data(invalid.utf8)))
    }

    func testAnExportedKeyWinsOverThePastedOne() throws {
        var sources = ElevenLabsCredentialSources()
        sources.environment = ["ELEVENLABS_API_KEY": " env-key \n"]
        sources.settingsKey = { "pasted-key" }
        XCTAssertEqual(try ElevenLabsCredentials.load(sources),
                       .init(key: "env-key", source: .environment))
        sources.environment = [:]
        XCTAssertEqual(try ElevenLabsCredentials.load(sources),
                       .init(key: "pasted-key", source: .settings))
        sources.settingsKey = { "  " }
        XCTAssertThrowsError(try ElevenLabsCredentials.load(sources))
    }
}
