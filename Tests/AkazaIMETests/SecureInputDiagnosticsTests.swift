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
}
