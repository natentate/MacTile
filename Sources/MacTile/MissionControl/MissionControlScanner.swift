import AppKit
import MacTileCore

/// One window thumbnail as Mission Control exposes it.
struct MissionControlThumbnail {
    let element: AXUIElement
    let title: String
    /// On-screen rect of the thumbnail (top-left global coordinates).
    let frame: CGRect
    /// Owning app, when the identifier carries it (macOS 27).
    let bundleID: String?
}

/// Reads Mission Control's window thumbnails through Accessibility.
///
/// Mission Control paints thumbnails itself, so they aren't real windows. Its UI is exposed as
/// an Accessibility tree instead: under the **Dock** up to macOS 26 (`mc` → `mc.display` →
/// `mc.windows` → buttons) and under **WindowManager** from macOS 27 (`mc.display` → buttons
/// identified `<bundle id>.space.<n>`). App Exposé uses `appexpose` equivalents. Both
/// layouts are searched, so either OS works.
enum MissionControlScanner {
    private static let sourceBundleIDs = ["com.apple.dock", "com.apple.WindowManager"]
    private static let rootIdentifiers: Set<String> = ["mc", "mc.display", "appexpose", "appexpose.display"]

    /// Thumbnails currently shown, or nil when Mission Control / App Exposé isn't open.
    static func scan() -> [MissionControlThumbnail]? {
        var roots: [AXUIElement] = []
        for bundleID in sourceBundleIDs {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                let element = AXUIElementCreateApplication(app.processIdentifier)
                element.setTimeout(0.2)
                findRoots(in: element, depth: 0, into: &roots)
            }
        }
        guard !roots.isEmpty else { return nil }

        var thumbnails: [MissionControlThumbnail] = []
        var seen: [CGRect] = []
        for root in roots {
            collectThumbnails(in: root, depth: 0, into: &thumbnails, seen: &seen)
        }
        // A root with nothing in it is the empty stub WindowManager-era Docks keep around.
        return thumbnails.isEmpty && roots.allSatisfy({ $0.children.isEmpty }) ? nil : thumbnails
    }

    private static func isRoot(_ element: AXUIElement) -> Bool {
        if let id = element.identifier, rootIdentifiers.contains(id) { return true }
        return element.role == kAXGroupRole && element.title == "Mission Control"
    }

    private static func findRoots(in element: AXUIElement, depth: Int, into roots: inout [AXUIElement]) {
        guard depth < 3 else { return }
        for child in element.children {
            if isRoot(child) {
                roots.append(child)
            } else if child.role == kAXGroupRole {
                findRoots(in: child, depth: depth + 1, into: &roots)
            }
        }
    }

    private static func collectThumbnails(
        in element: AXUIElement, depth: Int,
        into thumbnails: inout [MissionControlThumbnail], seen: inout [CGRect]
    ) {
        guard depth < 5 else { return }
        for child in element.children {
            let identifier = child.identifier
            // The Spaces bar (desktop thumbnails, "+") isn't a window.
            if let identifier, identifier.hasPrefix("mc.spaces") { continue }

            if child.role == kAXButtonRole {
                guard let frame = child.frame, frame.width > 40, frame.height > 30,
                      !seen.contains(where: { $0.isClose(to: frame, tolerance: 1) }) else { continue }
                seen.append(frame)
                let title = child.title ?? child.string(kAXDescriptionAttribute) ?? ""
                thumbnails.append(MissionControlThumbnail(
                    element: child, title: title, frame: frame,
                    bundleID: MissionControlIdentifier.bundleID(from: identifier)))
            } else {
                collectThumbnails(in: child, depth: depth + 1, into: &thumbnails, seen: &seen)
            }
        }
    }
}
