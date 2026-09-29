import XCTest
@testable import Codenotch

/// Pinned to what `higgsfield account status --json` (CLI 1.1.25) printed on
/// 29 Sep 2026, and to the two failures it was seen to give: no login and no
/// workspace. The amounts are synthetic.
final class HiggsfieldUsageTests: XCTestCase {
    private func output(_ stdout: String = #"{"credits":1038.15,"email":"a@example.com","subscription_plan_type":"ultimate"}"#,
                        stderr: String = "", status: Int32 = 0) -> HiggsfieldCLI.Output {
        HiggsfieldCLI.Output(status: status, stdout: stdout, stderr: stderr)
    }

    func testTheBalanceIsACountNotARing() throws {
        let reading = try HiggsfieldUsage.reading(from: output())
        let credits = try XCTUnwrap(reading.windows.first)
        XCTAssertNil(credits.usedFraction, "the CLI names no allowance, so there is no share to draw")
        XCTAssertEqual(credits.usedText, "1,038")
        XCTAssertEqual(credits.detail, "1,038 credits left")
        XCTAssertEqual(reading.plan, "Ultimate")
        XCTAssertEqual(reading.email, "a@example.com")
    }

    func testASignedOutCLIAsksForALogin() {
        let signedOut = output("", stderr: "Error: higgsfield: request failed (no response received)\nHint: Run: hf auth login\n",
                               status: 2)
        XCTAssertThrowsError(try HiggsfieldUsage.reading(from: signedOut)) { error in
            guard case UsageProviderError.needsAuth = error else { return XCTFail("\(error)") }
        }
    }

    func testAMissingWorkspaceIsNamedRatherThanCalledASignOut() {
        let noWorkspace = output("", stderr: "Error: No workspace selected.\nHint: Run: hf workspace set <workspace_id>\n",
                                 status: 4)
        XCTAssertThrowsError(try HiggsfieldUsage.reading(from: noWorkspace)) { error in
            guard case UsageProviderError.apiError(let message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("workspace set"))
        }
    }

    func testAnUnknownFailureCarriesTheCLIsOwnWords() {
        let other = output("", stderr: "Error: something new\n", status: 1)
        XCTAssertThrowsError(try HiggsfieldUsage.reading(from: other)) { error in
            guard case UsageProviderError.apiError(let message) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(message, "something new")
        }
    }

    func testAChangedShapeIsNotReadAsANumber() {
        XCTAssertThrowsError(try HiggsfieldUsage.reading(from: output(#"{"credits":"1038"}"#)))
        XCTAssertThrowsError(try HiggsfieldUsage.reading(from: output("not json")))
    }

    func testTheNpmLauncherIsFollowedToTheNativeBinary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("lib/cli/bin"), vendor = root.appendingPathComponent("lib/cli/vendor")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vendor, withIntermediateDirectories: true)
        let launcher = bin.appendingPathComponent("higgsfield.js"), native = vendor.appendingPathComponent("hf")
        for file in [launcher, native] {
            FileManager.default.createFile(atPath: file.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        }
        let link = root.appendingPathComponent("higgsfield")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: launcher)

        XCTAssertEqual(HiggsfieldCLI.native(link.path, fileManager: .default)?.resolvingSymlinksInPath().path,
                       native.resolvingSymlinksInPath().path)
        try FileManager.default.removeItem(at: native)
        XCTAssertNil(HiggsfieldCLI.native(link.path, fileManager: .default),
                     "a launcher with no binary beside it needs Node, which Finder does not provide")
    }
}
