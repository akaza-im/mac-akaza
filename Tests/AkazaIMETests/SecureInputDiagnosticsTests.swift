import Foundation
import XCTest

@testable import AkazaIME

final class SecureInputDiagnosticsTests: XCTestCase {
    func testLegitimateWhenHolderMatchesFrontmost() {
        XCTAssertTrue(
            SecureInputDiagnostics.isLegitimate(
                holderBundle: "com.google.Chrome",
                frontmostBundle: "com.google.Chrome"))
    }

    func testNotLegitimateWhenHolderDiffersFromFrontmost() {
        XCTAssertFalse(
            SecureInputDiagnostics.isLegitimate(
                holderBundle: "com.google.Chrome",
                frontmostBundle: "com.github.wez.wezterm"))
    }

    func testNotLegitimateWhenHolderIsUnknown() {
        XCTAssertFalse(
            SecureInputDiagnostics.isLegitimate(
                holderBundle: nil,
                frontmostBundle: "com.google.Chrome"))
    }

    func testNotLegitimateWhenFrontmostIsUnknown() {
        XCTAssertFalse(
            SecureInputDiagnostics.isLegitimate(
                holderBundle: "com.google.Chrome",
                frontmostBundle: nil))
    }

    func testIsProcessAliveForCurrentProcess() {
        XCTAssertTrue(SecureInputDiagnostics.isProcessAlive(getpid()))
    }

    func testIsProcessAliveForExitedProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        XCTAssertFalse(SecureInputDiagnostics.isProcessAlive(process.processIdentifier))
    }
}

final class SecureInputNotifierTests: XCTestCase {
    func testBodyTextForAliveHolderSuggestsRestart() {
        let body = SecureInputNotifier.bodyText(holderName: "WezTerm")
        XCTAssertTrue(body.contains("WezTerm"))
        XCTAssertTrue(body.contains("再起動"))
    }

    func testBodyTextForUnknownHolderUsesFallbackName() {
        let body = SecureInputNotifier.bodyText(holderName: nil)
        XCTAssertTrue(body.contains("他のプロセス"))
    }

    func testDeadHolderBodyTextSuggestsScreenLockNotRestart() {
        let body = SecureInputNotifier.deadHolderBodyText(pid: 14345)
        XCTAssertTrue(body.contains("pid=14345"))
        XCTAssertTrue(body.contains("既に終了"))
        XCTAssertTrue(body.contains("画面をロック"))
        XCTAssertFalse(body.contains("再起動"))
    }
}
