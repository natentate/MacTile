import Foundation

/// Built-in snap positions available from the keyboard, menu bar, and edge snapping.
public enum SnapPreset: String, Codable, CaseIterable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case maximize, almostMaximize

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        }
    }

    public var rect: UnitRect {
        let third = 1.0 / 3.0
        switch self {
        case .leftHalf: return UnitRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return UnitRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return UnitRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return UnitRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: return UnitRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return UnitRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .leftThird: return UnitRect(x: 0, y: 0, width: third, height: 1)
        case .centerThird: return UnitRect(x: third, y: 0, width: third, height: 1)
        case .rightThird: return UnitRect(x: 2 * third, y: 0, width: third, height: 1)
        case .leftTwoThirds: return UnitRect(x: 0, y: 0, width: 2 * third, height: 1)
        case .rightTwoThirds: return UnitRect(x: third, y: 0, width: 2 * third, height: 1)
        case .maximize: return .full
        case .almostMaximize: return UnitRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        }
    }

    /// Groups used to lay out menus and the shortcut list.
    public static let groups: [[SnapPreset]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds],
        [.maximize, .almostMaximize],
    ]
}

/// Everything MacTile can do in response to a shortcut or menu item.
public enum WindowAction: Codable, Hashable {
    case preset(SnapPreset)
    case zone(layoutID: UUID, zoneID: UUID)
    case workspace(UUID)
    case restore
    case center
    case nextDisplay
    case previousDisplay
    case quickLayout
    case layoutPicker
    case toggleEnabled

    /// Actions that don't depend on user-defined layouts or workspaces.
    public static let general: [WindowAction] = [
        .restore, .center, .nextDisplay, .previousDisplay, .quickLayout, .layoutPicker, .toggleEnabled,
    ]

    public var generalTitle: String? {
        switch self {
        case .restore: return "Restore Previous Size"
        case .center: return "Center Window"
        case .nextDisplay: return "Move to Next Display"
        case .previousDisplay: return "Move to Previous Display"
        case .quickLayout: return "Quick Layout…"
        case .layoutPicker: return "Show Layout Picker…"
        case .toggleEnabled: return "Pause / Resume MacTile"
        case .preset(let preset): return preset.title
        case .zone, .workspace: return nil
        }
    }
}
