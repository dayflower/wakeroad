import XCTest

@testable import WakeRoadCore

final class WatchRootsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchRootsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
        try super.tearDownWithError()
    }

    // MARK: - parseWatchSpec

    func testParseWatchSpecWithoutExtensionsUsesDefaults() {
        let (path, extensions) = WatchRoots.parseWatchSpec("~/proj")
        XCTAssertEqual(path, "~/proj")
        XCTAssertEqual(extensions, Agent.transcriptExtensions)
    }

    func testParseWatchSpecWithExtensions() {
        let (path, extensions) = WatchRoots.parseWatchSpec("~/proj=md, log")
        XCTAssertEqual(path, "~/proj")
        XCTAssertEqual(extensions, ["md", "log"])
    }

    func testParseWatchSpecTreatsEqualsInPathAsPath() {
        // The text after the last `=` contains a slash, so it is part of the path.
        let (path, extensions) = WatchRoots.parseWatchSpec("~/a=b/c")
        XCTAssertEqual(path, "~/a=b/c")
        XCTAssertEqual(extensions, Agent.transcriptExtensions)
    }

    // MARK: - resolve(custom:)

    func testResolveCustomExpandsAndFiltersExtensions() {
        let custom = [
            CustomWatchTarget(name: "Docs", path: dir.path, extensionsRaw: "MD, md, txt"),
            CustomWatchTarget(name: "Gone", path: dir.path + "/missing", extensionsRaw: "log"),
            CustomWatchTarget(name: "NoExt", path: dir.path, extensionsRaw: "  "),
        ]
        let resolved = WatchRoots.resolve(custom: custom)
        let docs = try? XCTUnwrap(resolved.first { $0.name == "Docs" })
        XCTAssertEqual(docs?.extensions, ["md", "txt"])
        XCTAssertFalse(resolved.contains { $0.name == "Gone" })
        XCTAssertFalse(resolved.contains { $0.name == "NoExt" })
    }

    func testResolveCustomFallsBackToDirectoryNameWhenBlank() {
        let custom = [CustomWatchTarget(name: "  ", path: dir.path, extensionsRaw: "log")]
        let resolved = WatchRoots.resolve(custom: custom)
        XCTAssertTrue(resolved.contains { $0.name == dir.lastPathComponent })
    }

    // MARK: - resolve(cliWatchSpecs:)

    // The dir name is unique per test, so match on it: the resolved root is
    // canonicalized (symlinks resolved) and may differ from `dir.path`.
    private var dirName: String { dir.lastPathComponent }

    func testResolveCLISpecsAppliesInlineExtensions() {
        let resolved = WatchRoots.resolve(cliWatchSpecs: [dir.path + "=md,log"])
        let target = try? XCTUnwrap(resolved.first { $0.name == dirName })
        XCTAssertEqual(target?.extensions, ["md", "log"])
    }

    func testResolveCLISpecsDefaultsExtensions() {
        let resolved = WatchRoots.resolve(cliWatchSpecs: [dir.path])
        let target = try? XCTUnwrap(resolved.first { $0.name == dirName })
        XCTAssertEqual(target?.extensions, Agent.transcriptExtensions)
    }

    func testResolveCLICombinesConfigTargetsAndSpecs() {
        let config = [CustomWatchTarget(name: "FromFile", path: dir.path, extensionsRaw: "md")]
        let resolved = WatchRoots.resolveCLI(
            configTargets: config, watchSpecs: [dir.path + "=log"], includeDefaults: false)
        // Config target and --watch spec both resolve for the same dir.
        XCTAssertTrue(resolved.contains { $0.name == "FromFile" && $0.extensions == ["md"] })
        XCTAssertTrue(resolved.contains { $0.name == dirName && $0.extensions == ["log"] })
    }

    func testResolveCLIIncludesBuiltInsOnlyWhenRequested() {
        let builtInNames = Set(Agent.known.map(\.name))
        // Restrict to existing built-in roots so the assertion is about the
        // includeDefaults flag, not whether the agent directories happen to exist.
        let existingBuiltIns = Set(
            WatchRoots.resolveCLI(configTargets: [], watchSpecs: [], includeDefaults: true)
                .map(\.name)
        ).intersection(builtInNames)

        let without = WatchRoots.resolveCLI(
            configTargets: [], watchSpecs: [], includeDefaults: false)
        XCTAssertTrue(Set(without.map(\.name)).isDisjoint(with: builtInNames))

        let with = WatchRoots.resolveCLI(configTargets: [], watchSpecs: [], includeDefaults: true)
        XCTAssertEqual(Set(with.map(\.name)).intersection(builtInNames), existingBuiltIns)
    }
}
