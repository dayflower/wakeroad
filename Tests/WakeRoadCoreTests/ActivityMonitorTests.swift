import XCTest
@testable import WakeRoadCore

/// In-memory stand-in for `SleepInhibitor` that records calls.
private final class FakeInhibitor: SleepInhibiting, @unchecked Sendable {
    var acquireResult = true
    private(set) var acquireCount = 0
    private(set) var releaseCount = 0
    private(set) var isHeld = false

    @discardableResult
    func acquire() -> Bool {
        acquireCount += 1
        guard acquireResult else { return false }
        isHeld = true
        return true
    }

    func release() {
        releaseCount += 1
        isHeld = false
    }
}

/// Mutable clock injected as the monitor's `now` closure.
private final class FakeClock: @unchecked Sendable {
    var current = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func advance(by interval: TimeInterval) {
        current += interval
    }
}

final class ActivityMonitorTests: XCTestCase {
    private var inhibitor = FakeInhibitor()
    private var clock = FakeClock()
    private var statuses: [MonitorStatus] = []

    override func setUp() {
        super.setUp()
        inhibitor = FakeInhibitor()
        clock = FakeClock()
        statuses = []
    }

    /// The timer is never started in tests, so the queue is inert and all
    /// calls stay synchronous on the test thread.
    private func makeMonitor(timeout: TimeInterval = 300) -> ActivityMonitor {
        let clock = self.clock
        let monitor = ActivityMonitor(
            timeout: timeout,
            inhibitor: inhibitor,
            queue: DispatchQueue(label: "test"),
            now: { clock.current }
        )
        monitor.onStatusChange = { [weak self] status in
            self?.statuses.append(status)
        }
        return monitor
    }

    // MARK: - Activity

    func testFirstActivityAcquiresAssertion() {
        let monitor = makeMonitor()
        monitor.recordActivity(path: "/tmp/a.jsonl")

        XCTAssertTrue(inhibitor.isHeld)
        XCTAssertEqual(inhibitor.acquireCount, 1)
        XCTAssertEqual(statuses.last?.isActive, true)
        XCTAssertEqual(statuses.last?.lastTrigger, "/tmp/a.jsonl")
        XCTAssertEqual(statuses.last?.lastActivity, clock.current)
    }

    func testActivityWhileActiveDoesNotReacquire() {
        let monitor = makeMonitor()
        monitor.recordActivity(path: "/tmp/a.jsonl")
        clock.advance(by: 10)
        monitor.recordActivity(path: "/tmp/b.jsonl")

        XCTAssertEqual(inhibitor.acquireCount, 1)
        XCTAssertEqual(statuses.last?.isActive, true)
        XCTAssertEqual(statuses.last?.lastTrigger, "/tmp/b.jsonl")
    }

    func testFailedAcquireStaysIdle() {
        inhibitor.acquireResult = false
        let monitor = makeMonitor()
        monitor.recordActivity(path: "/tmp/a.jsonl")

        XCTAssertFalse(inhibitor.isHeld)
        XCTAssertTrue(statuses.isEmpty)
    }

    // MARK: - Idle timeout

    func testIdleCheckReleasesAfterTimeout() {
        let monitor = makeMonitor(timeout: 300)
        monitor.recordActivity(path: "/tmp/a.jsonl")
        clock.advance(by: 301)
        monitor.checkIdle()

        XCTAssertFalse(inhibitor.isHeld)
        XCTAssertEqual(inhibitor.releaseCount, 1)
        XCTAssertEqual(statuses.last?.isActive, false)
    }

    func testIdleCheckKeepsAssertionWithinTimeout() {
        let monitor = makeMonitor(timeout: 300)
        monitor.recordActivity(path: "/tmp/a.jsonl")
        clock.advance(by: 299)
        monitor.checkIdle()

        XCTAssertTrue(inhibitor.isHeld)
        XCTAssertEqual(inhibitor.releaseCount, 0)
    }

    func testIdleCheckWhenIdleDoesNothing() {
        let monitor = makeMonitor()
        monitor.checkIdle()

        XCTAssertEqual(inhibitor.releaseCount, 0)
        XCTAssertTrue(statuses.isEmpty)
    }

    func testTimeoutChangeTakesEffectAtNextCheck() {
        let monitor = makeMonitor(timeout: 300)
        monitor.recordActivity(path: "/tmp/a.jsonl")
        clock.advance(by: 100)
        monitor.timeout = 60
        monitor.checkIdle()

        XCTAssertFalse(inhibitor.isHeld)
    }

    // MARK: - Suspend / resume

    func testSuspendWhileActiveReleasesAssertion() {
        let monitor = makeMonitor()
        monitor.recordActivity(path: "/tmp/a.jsonl")
        monitor.suspend()

        XCTAssertFalse(inhibitor.isHeld)
        XCTAssertEqual(statuses.last?.isActive, false)
        XCTAssertEqual(statuses.last?.isSuspended, true)
    }

    func testSuspendWhileIdleStillNotifies() {
        let monitor = makeMonitor()
        monitor.suspend()

        XCTAssertEqual(inhibitor.releaseCount, 0)
        XCTAssertEqual(statuses.count, 1)
        XCTAssertEqual(statuses.last?.isActive, false)
        XCTAssertEqual(statuses.last?.isSuspended, true)
    }

    func testActivityWhileSuspendedIsIgnored() {
        let monitor = makeMonitor()
        monitor.suspend()
        monitor.recordActivity(path: "/tmp/a.jsonl")

        XCTAssertEqual(inhibitor.acquireCount, 0)
        XCTAssertEqual(statuses.last?.isActive, false)
    }

    func testResumeReacquiresOnNextActivityOnly() {
        let monitor = makeMonitor()
        monitor.recordActivity(path: "/tmp/a.jsonl")
        monitor.suspend()
        monitor.resume()
        XCTAssertFalse(inhibitor.isHeld)
        XCTAssertEqual(statuses.last?.isSuspended, false)

        monitor.recordActivity(path: "/tmp/b.jsonl")
        XCTAssertTrue(inhibitor.isHeld)
        XCTAssertEqual(statuses.last?.isActive, true)
    }

    // MARK: - Stop

    func testStopWhileActiveReleasesAssertion() {
        let monitor = makeMonitor()
        monitor.recordActivity(path: "/tmp/a.jsonl")
        monitor.stop()

        XCTAssertFalse(inhibitor.isHeld)
        XCTAssertEqual(statuses.last?.isActive, false)
    }

    func testStopWhileIdleDoesNotNotify() {
        let monitor = makeMonitor()
        monitor.stop()

        XCTAssertEqual(inhibitor.releaseCount, 0)
        XCTAssertTrue(statuses.isEmpty)
    }

    // MARK: - Bootstrap

    func testBootstrapWithRecentWriteBecomesActive() {
        let monitor = makeMonitor(timeout: 300)
        let writeDate = clock.current - 100
        monitor.bootstrap(latestWrite: TranscriptWrite(path: "/tmp/a.jsonl", date: writeDate))

        XCTAssertTrue(inhibitor.isHeld)
        XCTAssertEqual(statuses.last?.isActive, true)
        XCTAssertEqual(statuses.last?.lastActivity, writeDate)
        XCTAssertEqual(statuses.last?.lastTrigger, "/tmp/a.jsonl")
    }

    func testBootstrapWithStaleWriteStaysIdle() {
        let monitor = makeMonitor(timeout: 300)
        let writeDate = clock.current - 301
        monitor.bootstrap(latestWrite: TranscriptWrite(path: "/tmp/a.jsonl", date: writeDate))

        XCTAssertFalse(inhibitor.isHeld)
        XCTAssertTrue(statuses.isEmpty)
    }

    func testBootstrapWithNoWriteStaysIdle() {
        let monitor = makeMonitor()
        monitor.bootstrap(latestWrite: nil)

        XCTAssertFalse(inhibitor.isHeld)
        XCTAssertTrue(statuses.isEmpty)
    }
}
