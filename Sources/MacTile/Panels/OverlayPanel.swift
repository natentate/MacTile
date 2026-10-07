import AppKit
import MacTileCore

/// Borderless, non-activating panel used for every overlay. It floats above normal
/// windows on all Spaces (including full-screen ones) and never steals focus from the
/// app whose window is being arranged.
final class OverlayPanel: NSPanel {
    /// Interactive overlays (Quick Layout, layout picker) need key status for Esc.
    var allowsKey = false
    var onCancel: (() -> Void)?

    init(level: NSWindow.Level, interactive: Bool = false) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = !interactive
        allowsKey = interactive
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(KeyCodes.escape) {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Shared drawing for layout thumbnails (drag panel, layout picker).
enum ThumbnailRenderer {
    static func draw(layout: TileLayout, in rect: CGRect, highlightedZone: UUID?, showNumbers: Bool) {
        let background = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.28).setFill()
        background.fill()

        for (index, zone) in layout.zones.enumerated() {
            let zoneRect = LayoutGeometry.rect(for: zone.rect, in: rect.insetBy(dx: 3, dy: 3), inset: 1.5)
            let path = NSBezierPath(roundedRect: zoneRect, xRadius: 3, yRadius: 3)
            let isHighlighted = zone.id == highlightedZone
            (isHighlighted ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.2)).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(isHighlighted ? 0.9 : 0.35).setStroke()
            path.lineWidth = 1
            path.stroke()

            if showNumbers, zoneRect.width > 14, zoneRect.height > 14 {
                drawCentered("\(index + 1)", in: zoneRect, size: min(13, zoneRect.height * 0.45),
                             color: NSColor.white.withAlphaComponent(isHighlighted ? 1 : 0.7))
            }
        }
    }

    static func drawCentered(_ text: String, in rect: CGRect, size: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        string.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }

    static func drawLabel(_ text: String, in rect: CGRect, alignment: NSTextAlignment, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let height = string.size().height
        string.draw(in: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height))
    }
}
