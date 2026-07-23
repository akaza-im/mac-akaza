import Foundation
import XCTest

@testable import AkazaIME

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testShowPredictiveCandidatesDefaultsToTrue() {
        let settings = Settings(defaults: defaults)

        XCTAssertTrue(settings.showPredictiveCandidates)
    }

    func testNotifyOnSecureInputDefaultsToFalse() {
        let settings = Settings(defaults: defaults)

        XCTAssertFalse(settings.notifyOnSecureInput)
    }

    func testNotifyOnSecureInputPersistsTrueAndFalseValues() {
        let settings = Settings(defaults: defaults)

        settings.notifyOnSecureInput = true
        XCTAssertTrue(Settings(defaults: defaults).notifyOnSecureInput)

        settings.notifyOnSecureInput = false
        XCTAssertFalse(Settings(defaults: defaults).notifyOnSecureInput)
    }

    func testShowPredictiveCandidatesPersistsFalseAndTrueValues() {
        let settings = Settings(defaults: defaults)

        settings.showPredictiveCandidates = false
        XCTAssertFalse(Settings(defaults: defaults).showPredictiveCandidates)

        settings.showPredictiveCandidates = true
        XCTAssertTrue(Settings(defaults: defaults).showPredictiveCandidates)
    }
}
