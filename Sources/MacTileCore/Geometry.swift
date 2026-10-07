import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Converts between unit rects and real frames.
///
/// All rects here use **top-left-origin** coordinates (the Accessibility API's space),
/// so `area.minY` is the top edge of the usable area.
public enum LayoutGeometry {
    /// The window frame for a unit rect inside `area`, with `gap` points around screen
    /// edges and `gap` points between neighbouring zones (half on each side).
    public static func frame(for unit: UnitRect, in area: CGRect, gap: CGFloat = 0) -> CGRect {
        let epsilon = 0.0005
        let minX = area.minX + CGFloat(unit.minX) * area.width
        let maxX = area.minX + CGFloat(unit.maxX) * area.width
        let minY = area.minY + CGFloat(unit.minY) * area.height
        let maxY = area.minY + CGFloat(unit.maxY) * area.height

        let left = unit.minX <= epsilon ? gap : gap / 2
        let right = unit.maxX >= 1 - epsilon ? gap : gap / 2
        let top = unit.minY <= epsilon ? gap : gap / 2
        let bottom = unit.maxY >= 1 - epsilon ? gap : gap / 2

        let rect = CGRect(
            x: minX + left,
            y: minY + top,
            width: max(maxX - minX - left - right, 1),
            height: max(maxY - minY - top - bottom, 1)
        )
        return CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
                      width: rect.width.rounded(), height: rect.height.rounded())
    }

    /// The unit rect a frame occupies inside `area` (ignores gaps).
    public static func unitRect(for frame: CGRect, in area: CGRect) -> UnitRect {
        guard area.width > 0, area.height > 0 else { return .full }
        return UnitRect(
            x: Double((frame.minX - area.minX) / area.width),
            y: Double((frame.minY - area.minY) / area.height),
            width: Double(frame.width / area.width),
            height: Double(frame.height / area.height)
        )
    }

    /// A point's position inside `area` as unit coordinates.
    public static func unitPoint(_ point: CGPoint, in area: CGRect) -> (x: Double, y: Double) {
        guard area.width > 0, area.height > 0 else { return (0, 0) }
        return (Double((point.x - area.minX) / area.width), Double((point.y - area.minY) / area.height))
    }

    /// Positions a unit rect inside an arbitrary rect (used for thumbnails), top-left origin.
    public static func rect(for unit: UnitRect, in bounds: CGRect, inset: CGFloat = 0) -> CGRect {
        CGRect(
            x: bounds.minX + CGFloat(unit.minX) * bounds.width,
            y: bounds.minY + CGFloat(unit.minY) * bounds.height,
            width: CGFloat(unit.width) * bounds.width,
            height: CGFloat(unit.height) * bounds.height
        ).insetBy(dx: inset, dy: inset)
    }

    /// `rect` moved so it lies inside `bounds` (as far as it fits).
    public static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var r = rect
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        return r
    }
}

/// Classic edge snapping: drag to an edge for a half, to a corner for a quarter,
/// to the top for maximize.
public enum EdgeSnap {
    /// - Parameters:
    ///   - point: the pointer, top-left coordinates.
    ///   - screenFrame: the display's full frame (including the menu bar), top-left coordinates.
    ///   - threshold: how close to an edge the pointer must be.
    ///   - cornerSize: how far along an edge a corner region extends.
    ///   - allowTop: whether the top edge maximizes (off when the top edge opens the panel).
    public static func preset(
        for point: CGPoint,
        screenFrame: CGRect,
        threshold: CGFloat = 6,
        cornerSize: CGFloat = 140,
        allowTop: Bool = true
    ) -> SnapPreset? {
        let nearLeft = point.x - screenFrame.minX <= threshold
        let nearRight = screenFrame.maxX - point.x <= threshold
        let nearTop = point.y - screenFrame.minY <= threshold
        let nearBottom = screenFrame.maxY - point.y <= threshold

        let inTopBand = point.y - screenFrame.minY <= cornerSize
        let inBottomBand = screenFrame.maxY - point.y <= cornerSize
        let inLeftBand = point.x - screenFrame.minX <= cornerSize
        let inRightBand = screenFrame.maxX - point.x <= cornerSize

        if nearLeft {
            if inTopBand { return .topLeft }
            if inBottomBand { return .bottomLeft }
            return .leftHalf
        }
        if nearRight {
            if inTopBand { return .topRight }
            if inBottomBand { return .bottomRight }
            return .rightHalf
        }
        if nearTop {
            guard allowTop else { return nil }
            if inLeftBand { return .topLeft }
            if inRightBand { return .topRight }
            return .maximize
        }
        if nearBottom {
            if inLeftBand { return .bottomLeft }
            if inRightBand { return .bottomRight }
        }
        return nil
    }
}

/// Maps a rubber-band selection on a grid to a unit rect (Quick Layout).
public enum QuickLayoutGrid {
    public struct Cell: Hashable {
        public var column: Int
        public var row: Int
        public init(column: Int, row: Int) {
            self.column = column
            self.row = row
        }
    }

    public static func cell(atX x: Double, y: Double, columns: Int, rows: Int) -> Cell {
        let cols = max(columns, 1)
        let rws = max(rows, 1)
        let c = min(max(Int(x * Double(cols)), 0), cols - 1)
        let r = min(max(Int(y * Double(rws)), 0), rws - 1)
        return Cell(column: c, row: r)
    }

    public static func unitRect(from a: Cell, to b: Cell, columns: Int, rows: Int) -> UnitRect {
        let cols = Double(max(columns, 1))
        let rws = Double(max(rows, 1))
        let c0 = min(a.column, b.column), c1 = max(a.column, b.column)
        let r0 = min(a.row, b.row), r1 = max(a.row, b.row)
        return UnitRect(
            x: Double(c0) / cols, y: Double(r0) / rws,
            width: Double(c1 - c0 + 1) / cols, height: Double(r1 - r0 + 1) / rws
        )
    }
}
