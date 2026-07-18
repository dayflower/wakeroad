import Foundation
import IOKit.pwr_mgt

/// The subset of `SleepInhibitor` the monitor depends on, so the monitor can
/// be tested without touching IOKit.
public protocol SleepInhibiting: AnyObject {
    /// Acquires the assertion. Returns false if acquisition failed.
    @discardableResult
    func acquire() -> Bool
    /// Releases the assertion. Releasing while not held is a no-op.
    func release()
}

/// Wraps an IOKit power assertion. The kernel automatically releases the
/// assertion if the process dies, so a crash can never leave sleep inhibited.
/// Not internally synchronized: all calls must happen on one queue
/// (`@unchecked Sendable` so a reference can be handed to that queue).
public final class SleepInhibitor: SleepInhibiting, @unchecked Sendable {
    public enum Kind: Equatable, Sendable {
        /// Prevents idle system sleep; the display may still turn off.
        case system
        /// Prevents idle display sleep (implies keeping the system awake).
        case display

        var assertionType: CFString {
            switch self {
            case .system:
                return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
            case .display:
                return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
            }
        }
    }

    private static let assertionName = "wakeroad: AI agent activity detected"

    public private(set) var kind: Kind
    private let log: LogHandler
    private var assertionID: IOPMAssertionID?

    public init(kind: Kind, log: @escaping LogHandler = { _ in }) {
        self.kind = kind
        self.log = log
    }

    /// Acquires the assertion. Idempotent: a second call while held is a no-op.
    @discardableResult
    public func acquire() -> Bool {
        guard assertionID == nil else { return true }

        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kind.assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.assertionName as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            log("error: failed to create power assertion (IOReturn: 0x\(String(result, radix: 16)))")
            return false
        }
        assertionID = id
        return true
    }

    /// Releases the assertion. Idempotent: releasing while not held is a no-op.
    public func release() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }

    /// Switches the assertion kind. If the assertion is currently held it is
    /// released and re-acquired with the new kind.
    public func setKind(_ newKind: Kind) {
        guard newKind != kind else { return }
        let wasHeld = assertionID != nil
        if wasHeld { release() }
        kind = newKind
        if wasHeld { acquire() }
    }

    public var isHeld: Bool {
        assertionID != nil
    }

    deinit {
        release()
    }
}
