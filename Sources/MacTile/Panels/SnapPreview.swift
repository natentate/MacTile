import AppKit
import MacTileCore

/// The translucent rectangle showing where a window will land.
final class SnapPreview {
    private lazy var panel: OverlayPanel = {
        let panel = OverlayPanel(level: .floating)
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 2
        panel.contentView = view
        return panel
    }()

    private var currentFrame: CGRect?

    /// - Parameter axFrame: target frame in Accessibility coordinates.
    func show(axFrame: CGRect) {
        let frame = ScreenGeometry.flip(axFrame)
        guard frame != currentFrame || !panel.isVisible else { return }
        applyColors()

        if panel.isVisible, currentFrame != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
        currentFrame = frame
    }

    func hide() {
        guard currentFrame != nil || panel.isVisible else { return }
        panel.orderOut(nil)
        currentFrame = nil
    }

    private func applyColors() {
        guard let layer = panel.contentView?.layer else { return }
        let accent = NSColor.controlAccentColor
        layer.backgroundColor = accent.withAlphaComponent(0.22).cgColor
        layer.borderColor = accent.withAlphaComponent(0.85).cgColor
    }
}

/// Shows every zone of a layout across a display while dragging with the overlay
/// modifier held (FancyZones-style).
final class ZoneOverlay {
    private lazy var panel: OverlayPanel = {
        let panel = OverlayPanel(level: .floating)
        panel.contentView = self.view
        return panel
    }()

    private let view = ZoneOverlayView()
    private(set) var screen: NSScreen?

    var isVisible: Bool { panel.isVisible }

    func show(layout: TileLayout, on screen: NSScreen, gap: CGFloat) {
        if !panel.isVisible || self.screen != screen || view.layout != layout || view.gap != gap {
            self.screen = screen
            view.layout = layout
            view.gap = gap
            view.area = ScreenGeometry.usableArea(of: screen)
            panel.setFrame(screen.visibleFrame, display: true)
            view.frame = CGRect(origin: .zero, size: screen.visibleFrame.size)
            view.needsDisplay = true
            panel.orderFrontRegardless()
        }
    }

    func highlight(_ zoneID: UUID?) {
        view.highlighted = zoneID
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        view.highlighted = nil
        screen = nil
    }
}

final class ZoneOverlayView: NSView {
    var layout: TileLayout?
    var gap: CGFloat = 0
    var area: CGRect = .zero
    var highlighted: UUID? {
        didSet { if highlighted != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let layout else { return }
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()

        for (index, zone) in layout.zones.enumerated() {
            // Same math as the real snap, so the overlay matches the result exactly.
            let target = LayoutGeometry.frame(for: zone.rect, in: area, gap: max(gap, 6))
            let local = target.offsetBy(dx: -area.minX, dy: -area.minY).insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: local, xRadius: 12, yRadius: 12)
            let isHighlighted = zone.id == highlighted
            let accent = NSColor.controlAccentColor
            (isHighlighted ? accent.withAlphaComponent(0.35) : NSColor.white.withAlphaComponent(0.08)).setFill()
            path.fill()
            (isHighlighted ? accent : NSColor.white.withAlphaComponent(0.55)).setStroke()
            path.lineWidth = isHighlighted ? 3 : 1.5
            path.stroke()
            ThumbnailRenderer.drawCentered("\(index + 1)", in: local, size: min(64, local.height * 0.3),
                                           color: NSColor.white.withAlphaComponent(isHighlighted ? 0.95 : 0.6),
                                           weight: .bold)
        }
    }
}
