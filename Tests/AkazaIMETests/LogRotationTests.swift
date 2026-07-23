import Foundation
import XCTest

@testable import AkazaIME

final class LogRotationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogRotationTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        try super.tearDownWithError()
    }

    private var logFile: URL { tempDir.appendingPathComponent("akaza.log") }
    private var rotatedFile: URL { tempDir.appendingPathComponent("akaza.log.1") }

    func testDoesNothingWhenFileIsMissing() {
        XCTAssertFalse(LogRotation.rotateIfNeeded(at: logFile, maxBytes: 10))

        XCTAssertFalse(FileManager.default.fileExists(atPath: rotatedFile.path))
    }

    func testDoesNothingWhenFileIsWithinLimit() throws {
        try Data(repeating: 0x61, count: 10).write(to: logFile)

        XCTAssertFalse(LogRotation.rotateIfNeeded(at: logFile, maxBytes: 10))

        XCTAssertTrue(FileManager.default.fileExists(atPath: logFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rotatedFile.path))
    }

    func testRotatesWhenFileExceedsLimit() throws {
        try Data(repeating: 0x61, count: 11).write(to: logFile)

        XCTAssertTrue(LogRotation.rotateIfNeeded(at: logFile, maxBytes: 10))

        XCTAssertFalse(FileManager.default.fileExists(atPath: logFile.path))
        XCTAssertEqual(try Data(contentsOf: rotatedFile).count, 11)
    }

    func testReplacesExistingRotatedFile() throws {
        try Data(repeating: 0x62, count: 5).write(to: rotatedFile)
        try Data(repeating: 0x61, count: 11).write(to: logFile)

        XCTAssertTrue(LogRotation.rotateIfNeeded(at: logFile, maxBytes: 10))

        XCTAssertEqual(try Data(contentsOf: rotatedFile).count, 11)
    }
}
