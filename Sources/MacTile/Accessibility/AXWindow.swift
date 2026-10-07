import AppKit
import ApplicationServices

extension AXUIElement {
    func copyValue(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = copyValue(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func elements(_ attribute: String) -> [AXUIElement] {
        (copyValue(attribute) as? [AXUIElement]) ?? []
    }

    func string(_ attribute: String) -> String? {
        copyValue(attribute) as? String
    }

    func bool(_ attribute: String) -> Bool? {
        copyValue(attribute) as? Bool
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }
}

/// A thin wrapper over an Accessibility window element. Frames are in top-left-origin
/// global coordinates, the space the Accessibility API uses.
final class AXWindow {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    var key: WindowKey { WindowKey(element: element) }

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    var bundleIdentifier: String? {
        pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
    }

    var title: String? { element.string(kAXTitleAttribute) }
    var role: String? { element.string(kAXRoleAttribute) }
    var subrole: String? { element.string(kAXSubroleAttribute) }
    var isMinimized: Bool { element.bool(kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { element.bool("AXFullScreen") ?? false }
    var isResizable: Bool { element.isSettable(kAXSizeAttribute) }
    var isMovable: Bool { element.isSettable(kAXPositionAttribute) }

    /// Whether this is an ordinary window MacTile should manage.
    var isManageable: Bool {
        guard role == kAXWindowRole, !isFullScreen, !isMinimized else { return false }
        if let subrole, subrole == kAXSystemDialogSubrole || subrole == kAXFloatingWindowSubrole {
            return false
        }
        return isMovable
    }

    var position: CGPoint? {
        guard let value = element.copyValue(kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    var size: CGSize? {
        guard let value = element.copyValue(kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    func setPosition(_ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        element.set(kAXPositionAttribute, value)
    }

    func setSize(_ size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        element.set(kAXSizeAttribute, value)
    }

    /// Moves and resizes the window. Size is applied on both sides of the move so a window
    /// crossing onto a smaller display isn't clamped by its old position.
    func setFrame(_ frame: CGRect) {
        // "Enhanced user interface" (turned on by VoiceOver and some utilities) makes apps
        // animate geometry changes, which drops intermediate sets. Turn it off briefly.
        let app = pid.map { AXUIElementCreateApplication($0) }
        let enhanced = app?.bool("AXEnhancedUserInterface") ?? false
        if enhanced { app?.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        defer { if enhanced { app?.set("AXEnhancedUserInterface", kCFBooleanTrue) } }

        if isResizable { setSize(frame.size) }
        setPosition(frame.origin)
        if isResizable { setSize(frame.size) }
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    // MARK: Lookup

    /// The focused window of the frontmost app.
    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return mainWindow(of: app.processIdentifier)
    }

    /// The focused (or main, or first) window of an app.
    static func mainWindow(of pid: pid_t) -> AXWindow? {
        let app = AXUIElementCreateApplication(pid)
        if let window = app.element(kAXFocusedWindowAttribute) { return AXWindow(window) }
        if let window = app.element(kAXMainWindowAttribute) { return AXWindow(window) }
        if let window = app.elements(kAXWindowsAttribute).first { return AXWindow(window) }
        return nil
    }

    /// The window under a point (top-left global coordinates).
    static func window(at point: CGPoint) -> AXWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              var current = hit else { return nil }
        for _ in 0..<16 {
            if current.string(kAXRoleAttribute) == kAXWindowRole { return AXWindow(current) }
            if let window = current.element(kAXWindowAttribute) { return AXWindow(window) }
            guard let parent = current.element(kAXParentAttribute) else { break }
            current = parent
        }
        return nil
    }
}

/// Hashable identity for a window, used to remember pre-snap frames.
struct WindowKey: Hashable {
    let element: AXUIElement

    static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security.
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
