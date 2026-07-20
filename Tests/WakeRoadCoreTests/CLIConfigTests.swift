import XCTest

@testable import WakeRoadCore

final class CLIConfigTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIConfigTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
        try super.tearDownWithError()
    }

    private func write(_ json: String) throws -> String {
        let url = dir.appendingPathComponent("config.json")
        try Data(json.utf8).write(to: url)
        return url.path
    }

    func testDecodesAndMapsToCustomWatchTargets() throws {
        let path = try write(
            """
            {
              "watchTargets": [
                { "name": "Notes", "path": "~/notes", "extensions": ["md", "TXT"] },
                { "path": "~/logs", "extensions": ["log"] }
              ]
            }
            """)
        let config = try XCTUnwrap(CLIConfig.load(path: path, required: true))
        let targets = config.customWatchTargets
        XCTAssertEqual(targets.map(\.name), ["Notes", ""])
        XCTAssertEqual(targets[0].path, "~/notes")
        // extensionsRaw is joined and normalized lazily by `extensions`.
        XCTAssertEqual(targets[0].extensions, ["md", "txt"])
        XCTAssertEqual(targets[1].extensions, ["log"])
    }

    func testAbsentOptionalFileReturnsNil() throws {
        let missing = dir.appendingPathComponent("nope.json").path
        XCTAssertNil(try CLIConfig.load(path: missing, required: false))
    }

    func testAbsentRequiredFileThrowsNotFound() {
        let missing = dir.appendingPathComponent("nope.json").path
        XCTAssertThrowsError(try CLIConfig.load(path: missing, required: true)) { error in
            guard case CLIConfig.LoadError.notFound = error else {
                return XCTFail("expected notFound, got \(error)")
            }
        }
    }

    func testMalformedFileThrowsMalformed() throws {
        let path = try write("{ not valid json")
        XCTAssertThrowsError(try CLIConfig.load(path: path, required: false)) { error in
            guard case CLIConfig.LoadError.malformed = error else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }
}
