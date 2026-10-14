import Foundation

/// Reports "true" only after a condition has held continuously for `delay` seconds.
/// Used so the drag panel appears after a brief hold near the top of the screen, not on a
/// pass-through.
public struct DwellTracker: Equatable {
    public var delay: TimeInterval
    private var enteredAt: TimeInterval?

    public init(delay: TimeInterval) {
        self.delay = delay
    }

    /// Feeds the current state. Returns true once `inside` has been true for `delay`.
    @discardableResult
    public mutating func update(inside: Bool, now: TimeInterval) -> Bool {
        guard inside else {
            enteredAt = nil
            return false
        }
        if enteredAt == nil { enteredAt = now }
        return now - (enteredAt ?? now) >= delay
    }

    /// Seconds until the dwell completes, or nil when not currently inside.
    public func remaining(now: TimeInterval) -> TimeInterval? {
        enteredAt.map { max(delay - (now - $0), 0) }
    }

    public mutating func reset() {
        enteredAt = nil
    }
}
