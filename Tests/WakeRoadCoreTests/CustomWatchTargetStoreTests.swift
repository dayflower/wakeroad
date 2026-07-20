import XCTest

@testable import WakeRoadCore

final class CustomWatchTargetStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "CustomWatchTargetStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    func testSaveLoadRoundTrip() {
        let targets = [
            CustomWatchTarget(name: "Docs", path: "~/docs", extensionsRaw: "md, txt"),
            CustomWatchTarget(name: "Logs", path: "/var/logs", extensionsRaw: "log"),
        ]
        CustomWatchTargetStore.save(targets, to: defaults)
        XCTAssertEqual(CustomWatchTargetStore.load(from: defaults), targets)
    }

    func testFirstLaunchSeedsBuiltInAgents() {
        let seeded = CustomWatchTargetStore.load(from: defaults)
        XCTAssertEqual(seeded.map(\.name), Agent.known.map(\.name))
        for (target, agent) in zip(seeded, Agent.known) {
            XCTAssertEqual(target.path, "~/" + agent.homeRelativeRoot)
            XCTAssertEqual(target.extensions, [agent.fileExtension])
        }
        // Persisted, so a second load returns the same list without re-seeding.
        XCTAssertEqual(CustomWatchTargetStore.load(from: defaults), seeded)
    }

    func testEmptyAfterUserRemovesAllTargets() {
        // A persisted empty array must not be treated as first launch.
        CustomWatchTargetStore.save([], to: defaults)
        XCTAssertTrue(CustomWatchTargetStore.load(from: defaults).isEmpty)
    }

    func testMigratesLegacyExtraWatchRootsAlongsideSeeds() {
        defaults.set(["~/a", "~/b/c"], forKey: CustomWatchTargetStore.legacyExtraWatchRootsKey)

        let loaded = CustomWatchTargetStore.load(from: defaults)
        // Built-in seeds come first, then the migrated legacy roots.
        XCTAssertEqual(loaded.prefix(Agent.known.count).map(\.name), Agent.known.map(\.name))
        let migrated = Array(loaded.suffix(2))
        XCTAssertEqual(migrated.map(\.path), ["~/a", "~/b/c"])
        XCTAssertEqual(migrated.map(\.name), ["a", "c"])
        for target in migrated {
            XCTAssertEqual(target.extensions, Agent.transcriptExtensions)
        }
        // Legacy key removed and the new key written.
        XCTAssertNil(defaults.array(forKey: CustomWatchTargetStore.legacyExtraWatchRootsKey))
        XCTAssertNotNil(defaults.data(forKey: CustomWatchTargetStore.key))
    }

    func testLoadIsIdempotent() {
        defaults.set(["~/a"], forKey: CustomWatchTargetStore.legacyExtraWatchRootsKey)

        let first = CustomWatchTargetStore.load(from: defaults)
        let second = CustomWatchTargetStore.load(from: defaults)
        XCTAssertEqual(first, second)
    }
}
