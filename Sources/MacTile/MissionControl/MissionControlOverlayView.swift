import AppKit
import MacTileCore

/// Everything the Mission Control overlays draw, in top-left global coordinates. Every
/// display's overlay gets the same model and draws the part that falls on it.
struct MissionControlRenderModel {
    struct Strip {
        var background: CGRect
        var title: String?
        var titleRect: CGRect?
        var items: [(layout: TileLayout, rect: CGRect)]
    }

    var regions: [MissionControlController.Region] = []
    var strips: [Strip] = []
    var hoveredControl: MissionControlController.Control?
    var pressedControl: MissionControlController.Control?
}

final class MissionControlOverlayView: NSView {
    /// Top-left global coordinates of this view's top-left corner.
    var origin: CGPoint = .zero
    var model = MissionControlRenderModel()

    override var isFlipped: Bool { true }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        for strip in model.strips {
            let background = local(strip.background)
            guard background.intersects(bounds) else { continue }
            let path = NSBezierPath(roundedRect: background, xRadius: 12, yRadius: 12)
            NSColor(white: 0.08, alpha: 0.88).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()

            if let title = strip.title, let titleRect = strip.titleRect {
                ThumbnailRenderer.drawLabel(title, in: local(titleRect), alignment: .left,
                                            color: NSColor.white.withAlphaComponent(0.85))
            }
            for item in strip.items {
                ThumbnailRenderer.draw(layout: item.layout, in: local(item.rect),
                                       highlightedZone: highlightedZone(in: item.layout),
                                       showNumbers: false,
                                       highlightAll: isTileHovered(item.layout))
            }
        }

        for region in model.regions {
            let rect = local(region.rect)
            guard rect.intersects(bounds) else { continue }
            switch region.control {
            case .close, .minimize, .hide, .layouts:
                drawButton(region.control, in: rect)
            case .tileMenu:
                drawTilePill(region.control, in: rect)
            default:
                break
            }
        }
    }

    private func highlightedZone(in layout: TileLayout) -> UUID? {
        if case .zone(_, let layoutID, let zoneID)? = model.hoveredControl, layoutID == layout.id { return zoneID }
        return nil
    }

    private func isTileHovered(_ layout: TileLayout) -> Bool {
        if case .tile(_, let layoutID)? = model.hoveredControl { return layoutID == layout.id }
        return false
    }

    private func drawButton(_ control: MissionControlController.Control, in rect: CGRect) {
        let isHovered = model.hoveredControl == control
        let isPressed = model.pressedControl == control
        let circle = NSBezierPath(ovalIn: rect)
        let fill: NSColor
        if case .close = control, isHovered {
            fill = .systemRed
        } else if isHovered {
            fill = .controlAccentColor
        } else {
            fill = NSColor(white: 0.12, alpha: 0.9)
        }
        (isPressed ? fill.blended(withFraction: 0.3, of: .black) ?? fill : fill).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.55).setStroke()
        circle.lineWidth = 1
        circle.stroke()
        if let symbol = control.symbol {
            drawSymbol(symbol, in: rect, pointSize: 10)
        }
    }

    private func drawTilePill(_ control: MissionControlController.Control, in rect: CGRect) {
        let isActive = model.hoveredControl?.tileDisplay != nil && model.hoveredControl?.tileDisplay == control.tileDisplay
        let pill = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        (isActive ? NSColor.controlAccentColor : NSColor(white: 0.12, alpha: 0.9)).setFill()
        pill.fill()
        NSColor.white.withAlphaComponent(0.5).setStroke()
        pill.lineWidth = 1
        pill.stroke()
        drawSymbol("square.grid.2x2", in: CGRect(x: rect.minX + 10, y: rect.minY, width: 18, height: rect.height),
                   pointSize: 11)
        ThumbnailRenderer.drawLabel("Tile", in: CGRect(x: rect.minX + 32, y: rect.minY, width: rect.width - 40,
                                                       height: rect.height),
                                    alignment: .left, color: .white)
    }

    private func drawSymbol(_ name: String, in rect: CGRect, pointSize: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = image.size
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                              width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
