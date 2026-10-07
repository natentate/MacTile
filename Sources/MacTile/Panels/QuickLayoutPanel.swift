import AppKit
import MacTileCore

/// Quick Layout: a one-off layout defined by dragging across a grid. The selection is
/// previewed live on screen and applied to the window that was focused when it opened.
final class QuickLayoutPanel {
    private let view = QuickLayoutView()
    private lazy var panel: OverlayPanel = {
        let panel = OverlayPanel(level: .popUpMenu, interactive: true)
        panel.hasShadow = true
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.addSubview(self.view)
        panel.contentView = effect
        panel.onCancel = { [weak self] in self?.close() }
        return panel
    }()

    private let preview = SnapPreview()
    private var clickOutsideMonitor: Any?
    private var onSelect: ((UnitRect) -> Void)?
    private var frameForUnit: ((UnitRect) -> CGRect)?

    /// - Parameters:
    ///   - frameForUnit: maps a selection to the real frame (Accessibility coordinates), for the live preview.
    ///   - onSelect: called with the chosen rect when the user releases the mouse.
    func show(on screen: NSScreen, columns: Int, rows: Int,
              frameForUnit: @escaping (UnitRect) -> CGRect,
              onSelect: @escaping (UnitRect) -> Void) {
        self.onSelect = onSelect
        self.frameForUnit = frameForUnit

        let visible = screen.visibleFrame
        let width: CGFloat = 520
        let gridHeight = (width - 40) * visible.height / max(visible.width, 1)
        let size = CGSize(width: width, height: gridHeight + 40 + QuickLayoutView.headerHeight)
        let frame = CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                           width: size.width, height: size.height)

        view.columns = max(columns, 1)
        view.rows = max(rows, 1)
        view.selection = nil
        view.onChange = { [weak self] unit in self?.selectionChanged(unit) }
        view.onCommit = { [weak self] unit in self?.commit(unit) }
        view.onCancel = { [weak self] in self?.close() }

        panel.setFrame(frame, display: false)
        panel.contentView?.frame = CGRect(origin: .zero, size: size)
        view.frame = CGRect(origin: .zero, size: size)
        view.needsDisplay = true
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)

        if clickOutsideMonitor == nil {
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] _ in self?.close()
            }
        }
    }

    func close() {
        if let monitor = clickOutsideMonitor { NSEvent.removeMonitor(monitor) }
        clickOutsideMonitor = nil
        preview.hide()
        panel.orderOut(nil)
        onSelect = nil
        frameForUnit = nil
    }

    private func selectionChanged(_ unit: UnitRect?) {
        if let unit, let frameForUnit {
            preview.show(axFrame: frameForUnit(unit))
        } else {
            preview.hide()
        }
    }

    private func commit(_ unit: UnitRect) {
        let onSelect = self.onSelect
        close()
        onSelect?(unit)
    }
}

final class QuickLayoutView: NSView {
    static let headerHeight: CGFloat = 26

    var columns = 6
    var rows = 4
    var selection: (start: QuickLayoutGrid.Cell, end: QuickLayoutGrid.Cell)? {
        didSet { needsDisplay = true }
    }

    var onChange: ((UnitRect?) -> Void)?
    var onCommit: ((UnitRect) -> Void)?
    var onCancel: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var gridRect: CGRect {
        CGRect(x: 20, y: 20 + QuickLayoutView.headerHeight, width: bounds.width - 40,
               height: bounds.height - 40 - QuickLayoutView.headerHeight)
    }

    private var selectedUnit: UnitRect? {
        guard let selection else { return nil }
        return QuickLayoutGrid.unitRect(from: selection.start, to: selection.end, columns: columns, rows: rows)
    }

    private func cell(at event: NSEvent) -> QuickLayoutGrid.Cell {
        let point = convert(event.locationInWindow, from: nil)
        let unit = LayoutGeometry.unitPoint(point, in: gridRect)
        return QuickLayoutGrid.cell(atX: unit.x, y: unit.y, columns: columns, rows: rows)
    }

    override func draw(_ dirtyRect: NSRect) {
        ThumbnailRenderer.drawLabel(
            "Quick Layout — drag across the grid to size the window. Esc to cancel.",
            in: CGRect(x: 20, y: 12, width: bounds.width - 40, height: QuickLayoutView.headerHeight),
            alignment: .center, color: .secondaryLabelColor)

        let grid = gridRect
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: grid, xRadius: 8, yRadius: 8).fill()

        let selected = selectedUnit
        for row in 0..<rows {
            for column in 0..<columns {
                let unit = UnitRect(x: Double(column) / Double(columns), y: Double(row) / Double(rows),
                                    width: 1 / Double(columns), height: 1 / Double(rows))
                let rect = LayoutGeometry.rect(for: unit, in: grid.insetBy(dx: 4, dy: 4), inset: 2)
                let isSelected = selected.map {
                    $0.contains(x: unit.midX, y: unit.midY)
                } ?? false
                (isSelected ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.14)).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let cell = cell(at: event)
        selection = (cell, cell)
        onChange?(selectedUnit)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = selection?.start else { return }
        selection = (start, cell(at: event))
        onChange?(selectedUnit)
    }

    override func mouseUp(with event: NSEvent) {
        guard let unit = selectedUnit else { return }
        onCommit?(unit)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(KeyCodes.escape) {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
