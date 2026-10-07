import AppKit
import MacTileCore

/// Watches global mouse events to detect when the user drags a window, then offers the
/// three drop targets, in priority order:
///
/// 1. **Zone overlay** — holding the overlay modifier shows the display's layout full-screen.
/// 2. **Layout panel** — Mosaic-style thumbnails; drop on any zone of any layout.
/// 3. **Edge snapping** — halves, quarters and maximize at the screen edges.
///
/// Drags are detected by watching the window under the pointer actually move, so title
/// bars, toolbars and tab strips all work and resizes are ignored. Movement is read from
/// the window server, which reports bounds live; Accessibility positions often lag until
/// the pointer pauses, which made fast drags go unnoticed.
final class DragSnapController {
    private struct Pending {
        let window: AXWindow
        /// Accessibility frame when the drag was first seen (used for restore and unsnap).
        let frame: CGRect
        /// Window server id and bounds, when the window could be matched.
        let windowID: CGWindowID?
        let serverBounds: CGRect?
        /// Pointer position (Cocoa) when `frame` and `serverBounds` were captured.
        let pointer: CGPoint
    }

    private struct Session {
        let window: AXWindow
        /// Frame to restore to if the window ends up snapped.
        let restoreFrame: CGRect
    }

    private struct Target {
        let unit: UnitRect
        let screen: NSScreen
    }

    private enum Phase {
        case idle
        case pending(Pending)
        case dragging(Session)
    }

    private let state: AppState
    private let windows: WindowManager
    private let panel = LayoutPanel(interactive: false)
    private let preview = SnapPreview()
    private let overlay = ZoneOverlay()
    private var monitors: [Any] = []
    private var phase: Phase = .idle
    private var target: Target?

    init(state: AppState, windows: WindowManager) {
        self.state = state
        self.windows = windows
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        reset()
    }

    private func handle(_ event: NSEvent) {
        guard state.config.isEnabled else {
            if case .idle = phase {} else { reset() }
            return
        }
        switch event.type {
        case .leftMouseDown: mouseDown()
        case .leftMouseDragged: mouseDragged()
        case .leftMouseUp: mouseUp()
        case .flagsChanged:
            if case .dragging = phase { update() }
        default: break
        }
    }

    // MARK: Phases

    private func mouseDown() {
        reset()
        guard AccessibilityPermission.isTrusted else { return }
        let point = ScreenGeometry.flip(NSEvent.mouseLocation)
        guard let window = AXWindow.window(at: point), windows.canManage(window),
              let frame = window.frame, let pid = window.pid else { return }
        let server = WindowServer.window(at: point, ownedBy: pid)
        // Sample the pointer after the (possibly slow) lookups so it pairs with the frames.
        phase = .pending(Pending(window: window, frame: frame, windowID: server?.id,
                                 serverBounds: server?.bounds, pointer: NSEvent.mouseLocation))
    }

    private func mouseDragged() {
        switch phase {
        case .idle:
            return
        case .dragging:
            update()
        case .pending(let pending):
            let location = NSEvent.mouseLocation
            let distance = hypot(location.x - pending.pointer.x, location.y - pending.pointer.y)
            guard distance > 2 else { return }

            let before: CGRect
            let now: CGRect
            if let id = pending.windowID, let start = pending.serverBounds, let current = WindowServer.bounds(of: id) {
                before = start
                now = current
            } else if let current = pending.window.frame {
                before = pending.frame
                now = current
            } else {
                phase = .idle
                return
            }

            if !now.size.isClose(to: before.size) {
                // The window is being resized, not moved.
                phase = .idle
                return
            }
            if now.origin.isClose(to: before.origin, tolerance: 1) {
                // Pointer moved but the window didn't (yet): a text selection, a slider, or
                // an app that is slow to start the move. Keep watching for a while.
                if distance > 400 { phase = .idle }
                return
            }
            begin(pending)
        }
    }

    private func mouseUp() {
        defer { reset() }
        guard case .dragging(let session) = phase, let target else { return }
        let frame = windows.frame(for: target.unit, on: target.screen)
        let windows = self.windows
        // Let the system finish its own drag before resizing the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            windows.snap(session.window, to: frame, restoreFrame: session.restoreFrame)
        }
    }

    private func begin(_ pending: Pending) {
        var restoreFrame = pending.frame
        if state.config.restoreOnUnsnap,
           let size = windows.takeUnsnapSize(for: pending.window, frameAtDragStart: pending.frame),
           let current = pending.window.frame {
            // Give the window back its pre-snap size, keeping the pointer at the same
            // relative spot along the title bar so it stays "in hand".
            let pointer = ScreenGeometry.flip(NSEvent.mouseLocation)
            let ratio = current.width > 0 ? (pointer.x - current.minX) / current.width : 0.5
            let restored = CGRect(x: (pointer.x - ratio * size.width).rounded(), y: current.minY,
                                  width: size.width, height: size.height)
            pending.window.setFrame(restored)
            restoreFrame = restored
        }
        phase = .dragging(Session(window: pending.window, restoreFrame: restoreFrame))
        update()
    }

    private func update() {
        guard case .dragging = phase else { return }
        let config = state.config
        let location = NSEvent.mouseLocation
        let pointer = ScreenGeometry.flip(location)
        let flags = NSEvent.modifierFlags
        guard let screen = ScreenGeometry.screen(containing: location) else { return }

        var newTarget: Target?

        if config.zoneOverlayEnabled, flags.contains(config.zoneOverlayModifier.flags),
           let layout = config.overlayLayout(forDisplay: screen.displayKey) {
            panel.hide()
            overlay.show(layout: layout, on: screen, gap: CGFloat(config.gap))
            let unit = LayoutGeometry.unitPoint(pointer, in: ScreenGeometry.usableArea(of: screen))
            let zone = layout.zone(atX: unit.x, y: unit.y)
            overlay.highlight(zone?.id)
            if let zone { newTarget = Target(unit: zone.rect, screen: screen) }
        } else {
            overlay.hide()
            if shouldShowPanel(config: config, location: location, screen: screen, flags: flags) {
                panel.show(layouts: config.panelLayouts, style: config.panelStyle,
                           position: config.panelPosition, on: screen, cursor: location)
            } else {
                panel.hide()
            }

            if let hit = panel.hit(atScreenPoint: location) {
                panel.highlight(hit)
                newTarget = Target(unit: hit.zone.rect, screen: panel.screen ?? screen)
            } else {
                panel.highlight(nil)
                if config.edgeSnapping,
                   let preset = EdgeSnap.preset(for: pointer, screenFrame: ScreenGeometry.fullArea(of: screen),
                                                allowTop: config.panelTrigger != .topEdge) {
                    newTarget = Target(unit: preset.rect, screen: screen)
                }
            }
        }

        target = newTarget
        if let newTarget {
            preview.show(axFrame: windows.frame(for: newTarget.unit, on: newTarget.screen))
        } else {
            preview.hide()
        }
    }

    private func shouldShowPanel(config: Configuration, location: CGPoint, screen: NSScreen,
                                 flags: NSEvent.ModifierFlags) -> Bool {
        switch config.panelTrigger {
        case .never:
            return false
        case .always:
            return true
        case .modifier:
            return flags.contains(config.panelModifier.flags)
        case .topEdge:
            let nearTop = screen.frame.maxY - location.y <= 36
            let overPanel = panel.isVisible && panel.frame.insetBy(dx: -40, dy: -60).contains(location)
            return nearTop || overPanel
        }
    }

    private func reset() {
        phase = .idle
        target = nil
        panel.hide()
        preview.hide()
        overlay.hide()
    }
}
