import Foundation

/// When the layout panel appears during a window drag.
public enum PanelTrigger: String, Codable, CaseIterable {
    case always, modifier, topEdge, never

    public var title: String {
        switch self {
        case .always: return "Whenever a window is dragged"
        case .modifier: return "While holding a modifier key"
        case .topEdge: return "When dragged to the top of the screen"
        case .never: return "Never"
        }
    }
}

public enum DragModifier: String, Codable, CaseIterable {
    case shift, option, control, command

    public var title: String {
        switch self {
        case .shift: return "⇧ Shift"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        }
    }
}

/// The ways the drag panel can present layouts.
public enum PanelStyle: String, Codable, CaseIterable {
    case large, compact, list

    public var title: String {
        switch self {
        case .large: return "Large thumbnails"
        case .compact: return "Compact thumbnails"
        case .list: return "List"
        }
    }
}

public enum PanelPosition: String, Codable, CaseIterable {
    case top, center, cursor

    public var title: String {
        switch self {
        case .top: return "Top of screen"
        case .center: return "Center of screen"
        case .cursor: return "Near the pointer"
        }
    }
}

/// Everything the user can configure. Persisted as JSON by `ConfigStore`.
///
/// Decoding is lenient: any missing key falls back to its default, so older or
/// hand-edited files keep working as new settings are added.
public struct Configuration: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var isEnabled: Bool
    public var layouts: [TileLayout]
    public var bindings: [HotKeyBinding]
    public var workspaces: [Workspace]

    // Drag & drop panel
    public var panelTrigger: PanelTrigger
    public var panelModifier: DragModifier
    public var panelStyle: PanelStyle
    public var panelPosition: PanelPosition

    // Snapping
    public var edgeSnapping: Bool
    public var zoneOverlayEnabled: Bool
    public var zoneOverlayModifier: DragModifier
    /// Layout shown by the zone overlay unless a display overrides it.
    public var defaultLayoutID: UUID?
    /// Per-display overlay layout, keyed by a stable display identifier.
    public var displayLayouts: [String: UUID]
    public var restoreOnUnsnap: Bool
    /// Space in points between windows and around screen edges.
    public var gap: Double

    // Quick Layout
    public var quickLayoutColumns: Int
    public var quickLayoutRows: Int

    /// Bundle identifiers MacTile never touches.
    public var excludedBundleIDs: [String]

    public init(
        version: Int = Configuration.currentVersion,
        isEnabled: Bool = true,
        layouts: [TileLayout] = TileLayout.defaultLayouts(),
        bindings: [HotKeyBinding] = HotKeyBinding.defaults(),
        workspaces: [Workspace] = [],
        panelTrigger: PanelTrigger = .always,
        panelModifier: DragModifier = .option,
        panelStyle: PanelStyle = .large,
        panelPosition: PanelPosition = .top,
        edgeSnapping: Bool = true,
        zoneOverlayEnabled: Bool = true,
        zoneOverlayModifier: DragModifier = .shift,
        defaultLayoutID: UUID? = nil,
        displayLayouts: [String: UUID] = [:],
        restoreOnUnsnap: Bool = true,
        gap: Double = 0,
        quickLayoutColumns: Int = 6,
        quickLayoutRows: Int = 4,
        excludedBundleIDs: [String] = []
    ) {
        self.version = version
        self.isEnabled = isEnabled
        self.layouts = layouts
        self.bindings = bindings
        self.workspaces = workspaces
        self.panelTrigger = panelTrigger
        self.panelModifier = panelModifier
        self.panelStyle = panelStyle
        self.panelPosition = panelPosition
        self.edgeSnapping = edgeSnapping
        self.zoneOverlayEnabled = zoneOverlayEnabled
        self.zoneOverlayModifier = zoneOverlayModifier
        self.defaultLayoutID = defaultLayoutID
        self.displayLayouts = displayLayouts
        self.restoreOnUnsnap = restoreOnUnsnap
        self.gap = gap
        self.quickLayoutColumns = quickLayoutColumns
        self.quickLayoutRows = quickLayoutRows
        self.excludedBundleIDs = excludedBundleIDs
    }

    enum CodingKeys: String, CodingKey {
        case version, isEnabled, layouts, bindings, workspaces
        case panelTrigger, panelModifier, panelStyle, panelPosition
        case edgeSnapping, zoneOverlayEnabled, zoneOverlayModifier, defaultLayoutID, displayLayouts
        case restoreOnUnsnap, gap, quickLayoutColumns, quickLayoutRows, excludedBundleIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Configuration()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        layouts = try c.decodeIfPresent([TileLayout].self, forKey: .layouts) ?? d.layouts
        bindings = try c.decodeIfPresent([HotKeyBinding].self, forKey: .bindings) ?? d.bindings
        workspaces = try c.decodeIfPresent([Workspace].self, forKey: .workspaces) ?? d.workspaces
        panelTrigger = try c.decodeIfPresent(PanelTrigger.self, forKey: .panelTrigger) ?? d.panelTrigger
        panelModifier = try c.decodeIfPresent(DragModifier.self, forKey: .panelModifier) ?? d.panelModifier
        panelStyle = try c.decodeIfPresent(PanelStyle.self, forKey: .panelStyle) ?? d.panelStyle
        panelPosition = try c.decodeIfPresent(PanelPosition.self, forKey: .panelPosition) ?? d.panelPosition
        edgeSnapping = try c.decodeIfPresent(Bool.self, forKey: .edgeSnapping) ?? d.edgeSnapping
        zoneOverlayEnabled = try c.decodeIfPresent(Bool.self, forKey: .zoneOverlayEnabled) ?? d.zoneOverlayEnabled
        zoneOverlayModifier = try c.decodeIfPresent(DragModifier.self, forKey: .zoneOverlayModifier)
            ?? d.zoneOverlayModifier
        defaultLayoutID = try c.decodeIfPresent(UUID.self, forKey: .defaultLayoutID)
        displayLayouts = try c.decodeIfPresent([String: UUID].self, forKey: .displayLayouts) ?? d.displayLayouts
        restoreOnUnsnap = try c.decodeIfPresent(Bool.self, forKey: .restoreOnUnsnap) ?? d.restoreOnUnsnap
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? d.gap
        quickLayoutColumns = try c.decodeIfPresent(Int.self, forKey: .quickLayoutColumns) ?? d.quickLayoutColumns
        quickLayoutRows = try c.decodeIfPresent(Int.self, forKey: .quickLayoutRows) ?? d.quickLayoutRows
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? d.excludedBundleIDs
    }

    // MARK: Queries

    public func layout(withID id: UUID) -> TileLayout? {
        layouts.first { $0.id == id }
    }

    /// Layouts shown in the drag panel and layout picker, in user order.
    public var panelLayouts: [TileLayout] {
        layouts.filter { $0.showInPanel && !$0.zones.isEmpty }
    }

    /// The layout the zone overlay shows on a display.
    public func overlayLayout(forDisplay key: String) -> TileLayout? {
        if let id = displayLayouts[key], let layout = layout(withID: id) { return layout }
        if let id = defaultLayoutID, let layout = layout(withID: id) { return layout }
        return layouts.first { !$0.zones.isEmpty }
    }

    public func combo(for action: WindowAction) -> KeyCombo? {
        bindings.first { $0.action == action }?.combo
    }

    public func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    // MARK: Mutations

    /// Binds (or with `nil`, unbinds) a shortcut. A combo can only drive one action,
    /// so any other action using it loses the binding.
    public mutating func setCombo(_ combo: KeyCombo?, for action: WindowAction) {
        bindings.removeAll { $0.action == action || (combo != nil && $0.combo == combo) }
        if let combo {
            bindings.append(HotKeyBinding(action: action, combo: combo))
        }
    }

    /// Removes a layout along with every reference to it.
    public mutating func removeLayout(id: UUID) {
        layouts.removeAll { $0.id == id }
        bindings.removeAll {
            if case .zone(let layoutID, _) = $0.action { return layoutID == id }
            return false
        }
        displayLayouts = displayLayouts.filter { $0.value != id }
        if defaultLayoutID == id { defaultLayoutID = nil }
    }

    /// Drops bindings and assignments that point at zones which no longer exist.
    public mutating func pruneDanglingReferences() {
        let zoneIDs: [UUID: Set<UUID>] = Dictionary(
            layouts.map { ($0.id, Set($0.zones.map(\.id))) },
            uniquingKeysWith: { first, _ in first }
        )
        bindings.removeAll {
            if case .zone(let layoutID, let zoneID) = $0.action {
                return !(zoneIDs[layoutID]?.contains(zoneID) ?? false)
            }
            if case .workspace(let workspaceID) = $0.action {
                return !workspaces.contains { $0.id == workspaceID }
            }
            return false
        }
        for index in workspaces.indices {
            let valid = zoneIDs[workspaces[index].layoutID] ?? []
            workspaces[index].assignments.removeAll { !valid.contains($0.zoneID) }
        }
    }
}
