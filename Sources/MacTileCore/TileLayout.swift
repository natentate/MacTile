import Foundation

/// One drop target inside a layout.
public struct Zone: Codable, Hashable, Identifiable {
    public var id: UUID
    public var rect: UnitRect

    public init(id: UUID = UUID(), rect: UnitRect) {
        self.id = id
        self.rect = rect
    }
}

/// A named set of zones. Layouts are shown in the drag panel, bound to shortcuts,
/// and used by workspaces.
///
/// `columns` × `rows` is the snapping grid the editor uses. Zones are free-form unit
/// rects, so a layout can be a plain grid ("basic") or any arrangement ("advanced").
public struct TileLayout: Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var columns: Int
    public var rows: Int
    public var zones: [Zone]
    public var showInPanel: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        columns: Int,
        rows: Int,
        zones: [Zone],
        showInPanel: Bool = true
    ) {
        self.id = id
        self.name = name
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        self.zones = zones
        self.showInPanel = showInPanel
    }

    /// Builds a layout with one zone per grid cell.
    public static func grid(name: String, columns: Int, rows: Int, showInPanel: Bool = true) -> TileLayout {
        TileLayout(name: name, columns: columns, rows: rows,
               zones: gridZones(columns: columns, rows: rows), showInPanel: showInPanel)
    }

    /// Builds a layout from zones described on a `columns` × `rows` grid as
    /// `(column, row, columnSpan, rowSpan)`.
    public static func cells(
        name: String, columns: Int, rows: Int,
        _ cells: [(Int, Int, Int, Int)], showInPanel: Bool = true
    ) -> TileLayout {
        let cw = 1 / Double(max(columns, 1))
        let rh = 1 / Double(max(rows, 1))
        let zones = cells.map { c, r, cs, rs in
            Zone(rect: UnitRect(x: Double(c) * cw, y: Double(r) * rh,
                                width: Double(cs) * cw, height: Double(rs) * rh))
        }
        return TileLayout(name: name, columns: columns, rows: rows, zones: zones, showInPanel: showInPanel)
    }

    public static func gridZones(columns: Int, rows: Int) -> [Zone] {
        let cols = max(columns, 1)
        let rws = max(rows, 1)
        var zones: [Zone] = []
        for r in 0..<rws {
            for c in 0..<cols {
                zones.append(Zone(rect: UnitRect(
                    x: Double(c) / Double(cols), y: Double(r) / Double(rws),
                    width: 1 / Double(cols), height: 1 / Double(rws))))
            }
        }
        return zones
    }

    /// The zone under a unit-space point. When zones overlap, the smallest one wins so
    /// nested zones stay reachable.
    public func zone(atX x: Double, y: Double) -> Zone? {
        zones.filter { $0.rect.contains(x: x, y: y) }.min { $0.rect.area < $1.rect.area }
    }

    public func zone(withID id: UUID) -> Zone? {
        zones.first { $0.id == id }
    }

    public func index(ofZone id: UUID) -> Int? {
        zones.firstIndex { $0.id == id }
    }

    public enum SplitAxis {
        /// Side by side (a vertical divider).
        case leftRight
        /// Stacked (a horizontal divider).
        case topBottom
    }

    /// Splits a zone in two. The first half keeps the zone's identity so shortcuts bound
    /// to it survive. Returns the new zone's id.
    @discardableResult
    public mutating func split(zoneID: UUID, axis: SplitAxis) -> UUID? {
        guard let index = index(ofZone: zoneID) else { return nil }
        let r = zones[index].rect
        let first: UnitRect
        let second: UnitRect
        switch axis {
        case .leftRight:
            first = UnitRect(x: r.x, y: r.y, width: r.width / 2, height: r.height)
            second = UnitRect(x: r.x + r.width / 2, y: r.y, width: r.width / 2, height: r.height)
        case .topBottom:
            first = UnitRect(x: r.x, y: r.y, width: r.width, height: r.height / 2)
            second = UnitRect(x: r.x, y: r.y + r.height / 2, width: r.width, height: r.height / 2)
        }
        zones[index].rect = first
        let newZone = Zone(rect: second)
        zones.insert(newZone, at: index + 1)
        return newZone.id
    }

    /// A copy with fresh identifiers for the layout and every zone.
    public func duplicated(name: String? = nil) -> TileLayout {
        TileLayout(name: name ?? "\(self.name) Copy", columns: columns, rows: rows,
               zones: zones.map { Zone(rect: $0.rect) }, showInPanel: showInPanel)
    }
}

extension TileLayout {
    /// The layouts a fresh install starts with.
    public static func defaultLayouts() -> [TileLayout] {
        [
            .grid(name: "Halves", columns: 2, rows: 1),
            .grid(name: "Thirds", columns: 3, rows: 1),
            .grid(name: "Quarters", columns: 2, rows: 2),
            .cells(name: "Main + Side", columns: 3, rows: 1, [(0, 0, 2, 1), (2, 0, 1, 1)]),
            .cells(name: "Main + Stack", columns: 2, rows: 2, [(0, 0, 1, 2), (1, 0, 1, 1), (1, 1, 1, 1)]),
            .cells(name: "Center Focus", columns: 4, rows: 1, [(0, 0, 1, 1), (1, 0, 2, 1), (3, 0, 1, 1)]),
            .grid(name: "Six Grid", columns: 3, rows: 2),
            .cells(name: "Full Screen", columns: 1, rows: 1, [(0, 0, 1, 1)]),
        ]
    }

    /// Starting points offered by the "add layout" menu.
    public static let templates: [(name: String, make: () -> TileLayout)] = [
        ("Blank", { TileLayout(name: "New Layout", columns: 6, rows: 4, zones: []) }),
        ("Halves", { .grid(name: "Halves", columns: 2, rows: 1) }),
        ("Thirds", { .grid(name: "Thirds", columns: 3, rows: 1) }),
        ("Quarters", { .grid(name: "Quarters", columns: 2, rows: 2) }),
        ("Six Grid", { .grid(name: "Six Grid", columns: 3, rows: 2) }),
        ("Columns ×4", { .grid(name: "Four Columns", columns: 4, rows: 1) }),
        ("Rows ×2", { .grid(name: "Rows", columns: 1, rows: 2) }),
        ("Main + Stack", {
            .cells(name: "Main + Stack", columns: 2, rows: 2, [(0, 0, 1, 2), (1, 0, 1, 1), (1, 1, 1, 1)])
        }),
    ]
}
