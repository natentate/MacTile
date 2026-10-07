import AppKit
import MacTileCore

/// Converts between Cocoa's bottom-left-origin space and the Accessibility API's
/// top-left-origin space. Both are anchored to the primary display.
enum ScreenGeometry {
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Flips a rect between Cocoa and Accessibility coordinates (the transform is its own inverse).
    static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func flip(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// The display containing a Cocoa point, falling back to the nearest one.
    static func screen(containing point: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        if let hit = screens.first(where: { f in
            let r = f.frame
            return point.x >= r.minX && point.x <= r.maxX && point.y >= r.minY && point.y <= r.maxY
        }) {
            return hit
        }
        return screens.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
            ?? NSScreen.main
    }

    /// The display showing most of a window (frame in Accessibility coordinates).
    static func screen(forAXFrame frame: CGRect) -> NSScreen? {
        let cocoa = flip(frame)
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(cocoa)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (screen, area) }
        }
        return best?.screen ?? screen(containing: CGPoint(x: cocoa.midX, y: cocoa.midY))
    }

    /// Usable area (excluding menu bar and Dock) in Accessibility coordinates.
    static func usableArea(of screen: NSScreen) -> CGRect {
        flip(screen.visibleFrame)
    }

    /// Full display frame in Accessibility coordinates.
    static func fullArea(of screen: NSScreen) -> CGRect {
        flip(screen.frame)
    }

    /// Displays ordered left to right, then top to bottom.
    static var orderedScreens: [NSScreen] {
        NSScreen.screens.sorted {
            $0.frame.minX != $1.frame.minX ? $0.frame.minX < $1.frame.minX : $0.frame.maxY > $1.frame.maxY
        }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// A key that survives reboots and reconnects: name plus the panel's serial number.
    var displayKey: String {
        guard let id = displayID else { return localizedName }
        let serial = CGDisplaySerialNumber(id)
        return serial == 0 ? localizedName : "\(localizedName) #\(serial)"
    }
}

extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

extension CGSize {
    func isClose(to other: CGSize, tolerance: CGFloat = 2) -> Bool {
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

extension CGPoint {
    func isClose(to other: CGPoint, tolerance: CGFloat = 2) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

extension DragModifier {
    var flags: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .option: return .option
        case .control: return .control
        case .command: return .command
        }
    }
}

extension KeyCombo.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: KeyCombo.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        if contains(.shift) { flags.insert(.shift) }
        return flags
    }
}

extension KeyCombo {
    /// The character an `NSMenuItem` needs to display this shortcut, when there is one.
    var menuKeyEquivalent: String? {
        func function(_ key: Int) -> String { String(Character(UnicodeScalar(UInt16(key))!)) }
        switch keyCode {
        case KeyCodes.leftArrow: return function(NSLeftArrowFunctionKey)
        case KeyCodes.rightArrow: return function(NSRightArrowFunctionKey)
        case KeyCodes.upArrow: return function(NSUpArrowFunctionKey)
        case KeyCodes.downArrow: return function(NSDownArrowFunctionKey)
        case KeyCodes.returnKey: return "\r"
        case KeyCodes.space: return " "
        case KeyCodes.delete: return "\u{8}"
        case KeyCodes.tab: return "\t"
        default:
            let name = KeyCodes.name(for: keyCode)
            return name.count == 1 && name.unicodeScalars.allSatisfy(\.isASCII) ? name.lowercased() : nil
        }
    }
}
