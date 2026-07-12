import Foundation
import IOKit.pwr_mgt

/// Wraps an IOKit power assertion. The kernel automatically releases the
/// assertion if the process dies, so a crash can never leave sleep inhibited.
final class SleepInhibitor {
    enum Kind {
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

    private let kind: Kind
    private var assertionID: IOPMAssertionID?

    init(kind: Kind) {
        self.kind = kind
    }

    /// Acquires the assertion. Idempotent: a second call while held is a no-op.
    @discardableResult
    func acquire() -> Bool {
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
    func release() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }

    var isHeld: Bool {
        assertionID != nil
    }

    deinit {
        release()
    }
}
