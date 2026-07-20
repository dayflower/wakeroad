import XCTest

@testable import WakeRoadCore

final class WatchTargetTests: XCTestCase {
    private func target(_ name: String, _ root: String, _ extensions: Set<String> = ["jsonl"])
        -> WatchTarget
    {
        WatchTarget(name: name, root: root, extensions: extensions)
    }

    func testMatchingReturnsContainingTarget() {
        let targets = [
            target("A", "/home/user/a"),
            target("B", "/home/user/b"),
        ]
        XCTAssertEqual(
            WatchTarget.matching(path: "/home/user/b/sub/file.jsonl", in: targets)?.name,
            "B"
        )
    }

    func testMatchingReturnsNilWhenNoRootContainsPath() {
        let targets = [target("A", "/home/user/a")]
        XCTAssertNil(WatchTarget.matching(path: "/home/user/other/file.jsonl", in: targets))
    }

    func testMatchingPrefersMostSpecificNestedRoot() {
        let targets = [
            target("Outer", "/home/user/projects"),
            target("Inner", "/home/user/projects/app"),
        ]
        XCTAssertEqual(
            WatchTarget.matching(path: "/home/user/projects/app/x.jsonl", in: targets)?.name,
            "Inner"
        )
    }

    func testParseExtensionsNormalizes() {
        XCTAssertEqual(
            WatchTarget.parseExtensions(" JSONL , log ,, log,MD "),
            ["jsonl", "log", "md"]
        )
    }

    func testParseExtensionsEmptyYieldsEmptySet() {
        XCTAssertTrue(WatchTarget.parseExtensions("   ,, ").isEmpty)
        XCTAssertTrue(WatchTarget.parseExtensions("").isEmpty)
    }
}
