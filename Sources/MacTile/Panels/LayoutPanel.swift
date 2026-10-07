import AppKit
import MacTileCore

/// The Mosaic-style panel of layout thumbnails. While dragging a window the user drops
/// it onto a zone of any thumbnail; from the keyboard (layout picker) the user clicks one.
final class LayoutPanel {
    struct Hit: Equatable {
        let layoutID: UUID
        let zone: Zone
    }

    private let interactive: Bool
    private let view: LayoutPanelView
    private lazy var panel: OverlayPanel = makePanel()
    private var effectView: NSVisualEffectView?
    private var clickOutsideMonitor: Any?

    private(set) var screen: NSScreen?
    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }

    /// Interactive mode only.
    var onPick: ((Hit) -> Void)?
    var onCancel: (() -> Void)?

    init(interactive: Bool) {
        self.interactive = interactive
        self.view = LayoutPanelView(interactive: interactive)
    }

    func show(layouts: [TileLayout], style: PanelStyle, position: PanelPosition, on screen: NSScreen, cursor: CGPoint) {
        guard !layouts.isEmpty else {
            hide()
            return
        }
        if panel.isVisible, self.screen == screen, view.layouts == layouts, view.metrics?.style == style {
            return
        }

        let visible = screen.visibleFrame
        let metrics = PanelMetrics.make(style: style, count: layouts.count,
                                        aspect: visible.width / max(visible.height, 1))
        view.layouts = layouts
        view.metrics = metrics
        view.highlighted = nil

        let size = metrics.panelSize
        let origin: CGPoint
        switch position {
        case .top:
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 10)
        case .center:
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        case .cursor:
            origin = CGPoint(x: cursor.x - size.width / 2, y: cursor.y + 36)
        }
        let frame = LayoutGeometry.clamp(CGRect(origin: origin, size: size), into: visible.insetBy(dx: 8, dy: 8))

        panel.setFrame(frame, display: false)
        effectView?.frame = CGRect(origin: .zero, size: size)
        view.frame = CGRect(origin: .zero, size: size)
        view.needsDisplay = true
        self.screen = screen

        if interactive {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            installClickOutsideMonitor()
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        removeClickOutsideMonitor()
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        view.highlighted = nil
        screen = nil
    }

    /// Hit-tests a Cocoa screen point against the thumbnails.
    func hit(atScreenPoint point: CGPoint) -> Hit? {
        guard panel.isVisible, panel.frame.contains(point) else { return nil }
        let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
        return view.hit(at: local)
    }

    func highlight(_ hit: Hit?) {
        view.highlighted = hit
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(level: .popUpMenu, interactive: interactive)
        panel.hasShadow = true
        panel.onCancel = { [weak self] in self?.onCancel?() }

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.addSubview(view)
        panel.contentView = effect
        effectView = effect

        view.onPick = { [weak self] hit in self?.onPick?(hit) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        return panel
    }

    private func installClickOutsideMonitor() {
        guard clickOutsideMonitor == nil else { return }
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.onCancel?()
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor { NSEvent.removeMonitor(monitor) }
        clickOutsideMonitor = nil
    }
}

final class LayoutPanelView: NSView {
    var layouts: [TileLayout] = []
    var metrics: PanelMetrics?
    var highlighted: LayoutPanel.Hit? {
        didSet { if highlighted != oldValue { needsDisplay = true } }
    }

    var onPick: ((LayoutPanel.Hit) -> Void)?
    var onCancel: (() -> Void)?
    private let interactive: Bool
    private var trackingArea: NSTrackingArea?

    init(interactive: Bool) {
        self.interactive = interactive
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { interactive }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func hit(at point: CGPoint) -> LayoutPanel.Hit? {
        guard let metrics, let index = metrics.thumbnailIndex(at: point), index < layouts.count else { return nil }
        let layout = layouts[index]
        let thumb = metrics.thumbnailFrame(at: index).insetBy(dx: 3, dy: 3)
        let unit = LayoutGeometry.unitPoint(point, in: thumb)
        guard let zone = layout.zone(atX: unit.x, y: unit.y) else { return nil }
        return LayoutPanel.Hit(layoutID: layout.id, zone: zone)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let metrics else { return }
        for (index, layout) in layouts.enumerated() {
            let thumb = metrics.thumbnailFrame(at: index)
            let highlight = highlighted?.layoutID == layout.id ? highlighted?.zone.id : nil
            ThumbnailRenderer.draw(layout: layout, in: thumb, highlightedZone: highlight,
                                   showNumbers: metrics.style != .compact)
            if let label = metrics.labelFrame(at: index) {
                let isActive = highlight != nil
                ThumbnailRenderer.drawLabel(
                    layout.name, in: label,
                    alignment: metrics.style == .list ? .left : .center,
                    color: isActive ? .labelColor : .secondaryLabelColor)
            }
        }
    }

    // MARK: Interactive mode

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard interactive else { return }
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard interactive else { return }
        highlighted = hit(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard interactive else { return }
        highlighted = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard interactive else { return }
        if let hit = hit(at: convert(event.locationInWindow, from: nil)) {
            onPick?(hit)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(KeyCodes.escape) {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
