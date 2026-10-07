import AppKit
import MacTileCore

/// Moves and resizes windows, and remembers where they were before MacTile touched them
/// so they can be restored.
final class WindowManager {
    private let state: AppState
    /// Frame each window had before it was snapped.
    private var restoreFrames: [WindowKey: CGRect] = [:]
    /// Frame MacTile last gave each window, to detect whether it is still snapped.
    private var snappedFrames: [WindowKey: CGRect] = [:]

    init(state: AppState) {
        self.state = state
    }

    private var gap: CGFloat { CGFloat(max(state.config.gap, 0)) }

    // MARK: Targets

    /// The focused window, if MacTile is allowed to manage it.
    func focusedWindow() -> AXWindow? {
        guard let window = AXWindow.focused(), canManage(window) else { return nil }
        return window
    }

    func canManage(_ window: AXWindow) -> Bool {
        if window.pid == getpid() { return false }
        if state.config.isExcluded(bundleID: window.bundleIdentifier) { return false }
        return window.isManageable
    }

    func screen(of window: AXWindow) -> NSScreen? {
        window.frame.flatMap(ScreenGeometry.screen(forAXFrame:)) ?? NSScreen.main
    }

    /// The real frame (Accessibility coordinates) a unit rect maps to on a display.
    func frame(for unit: UnitRect, on screen: NSScreen) -> CGRect {
        LayoutGeometry.frame(for: unit, in: ScreenGeometry.usableArea(of: screen), gap: gap)
    }

    // MARK: Actions

    func apply(_ unit: UnitRect, to window: AXWindow, on screen: NSScreen? = nil) {
        guard let screen = screen ?? self.screen(of: window) else { return }
        snap(window, to: frame(for: unit, on: screen))
    }

    /// Sets a window's frame, remembering its previous frame for `restore`.
    /// - Parameter restoreFrame: the frame to restore to; defaults to the current frame
    ///   unless the window is already snapped (so repeated snaps keep the original).
    func snap(_ window: AXWindow, to frame: CGRect, restoreFrame: CGRect? = nil) {
        let key = window.key
        if let restoreFrame {
            restoreFrames[key] = restoreFrame
        } else if !isSnapped(window), let current = window.frame {
            restoreFrames[key] = current
        }
        window.setFrame(frame)
        // Apps may enforce minimum sizes; remember what we actually got.
        snappedFrames[key] = window.frame ?? frame
        pruneIfNeeded()
    }

    func restore(_ window: AXWindow) {
        let key = window.key
        guard let frame = restoreFrames.removeValue(forKey: key) else {
            NSSound.beep()
            return
        }
        snappedFrames.removeValue(forKey: key)
        window.setFrame(frame)
    }

    func isSnapped(_ window: AXWindow) -> Bool {
        guard let snapped = snappedFrames[window.key], let current = window.frame else { return false }
        return snapped.isClose(to: current, tolerance: 4)
    }

    /// When a snapped window is dragged away, returns the size it had before it was
    /// snapped and forgets the snap.
    func takeUnsnapSize(for window: AXWindow, frameAtDragStart: CGRect) -> CGSize? {
        let key = window.key
        guard let snapped = snappedFrames[key], snapped.isClose(to: frameAtDragStart, tolerance: 4),
              let original = restoreFrames[key] else { return nil }
        snappedFrames.removeValue(forKey: key)
        restoreFrames.removeValue(forKey: key)
        return original.size
    }

    func center(_ window: AXWindow) {
        guard let screen = screen(of: window), let current = window.frame else { return }
        let area = ScreenGeometry.usableArea(of: screen)
        let size = CGSize(width: min(current.width, area.width), height: min(current.height, area.height))
        let frame = CGRect(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        snap(window, to: frame)
    }

    /// Moves a window to the neighbouring display, keeping its relative position and size.
    func moveToAdjacentDisplay(_ window: AXWindow, forward: Bool) {
        let screens = ScreenGeometry.orderedScreens
        guard screens.count > 1, let current = screen(of: window), let frame = window.frame,
              let index = screens.firstIndex(of: current) else {
            NSSound.beep()
            return
        }
        let next = screens[(index + (forward ? 1 : -1) + screens.count) % screens.count]
        let unit = LayoutGeometry.unitRect(for: frame, in: ScreenGeometry.usableArea(of: current))
            .clamped(minSize: 0.05)
        let target = LayoutGeometry.frame(for: unit, in: ScreenGeometry.usableArea(of: next), gap: 0)
        snap(window, to: target)
    }

    /// Keeps the bookkeeping from growing without bound across long sessions.
    private func pruneIfNeeded() {
        guard snappedFrames.count > 300 else { return }
        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        let alive: (WindowKey) -> Bool = { key in
            var pid: pid_t = 0
            return AXUIElementGetPid(key.element, &pid) == .success && running.contains(pid)
        }
        snappedFrames = snappedFrames.filter { alive($0.key) }
        restoreFrames = restoreFrames.filter { alive($0.key) }
    }
}
