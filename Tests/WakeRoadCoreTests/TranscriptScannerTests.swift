import XCTest

@testable import WakeRoadCore

final class TranscriptScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func writeFile(_ relativePath: String, modifiedAt date: Date) throws -> String {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        // The scanner reports paths with symlinks resolved (/private/var/...
        // instead of /var/...), so return the canonical path for comparison.
        return try XCTUnwrap(url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath)
    }

    func testPicksMostRecentJSONLAcrossSubdirectories() throws {
        let older = Date(timeIntervalSinceNow: -600)
        let newer = Date(timeIntervalSinceNow: -60)
        _ = try writeFile("project-a/old.jsonl", modifiedAt: older)
        let newest = try writeFile("project-b/new.jsonl", modifiedAt: newer)

        let result = TranscriptScanner.latestWrite(in: [root.path])
        XCTAssertEqual(result?.path, newest)
        XCTAssertEqual(
            result!.date.timeIntervalSinceReferenceDate,
            newer.timeIntervalSinceReferenceDate,
            accuracy: 1
        )
    }

    func testIgnoresNonJSONLFiles() throws {
        _ = try writeFile("notes.txt", modifiedAt: Date())

        XCTAssertNil(TranscriptScanner.latestWrite(in: [root.path]))
    }

    func testMissingRootYieldsNil() {
        let missing = root.appendingPathComponent("does-not-exist").path
        XCTAssertNil(TranscriptScanner.latestWrite(in: [missing]))
    }
}
