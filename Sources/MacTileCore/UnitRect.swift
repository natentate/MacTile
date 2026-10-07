import Foundation

/// A rectangle expressed as fractions of a display's usable area.
///
/// The origin is the **top-left** corner and every component lives in `0...1`,
/// so a layout looks the same on any display regardless of resolution.
public struct UnitRect: Codable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = UnitRect(x: 0, y: 0, width: 1, height: 1)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { width * height }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= minX && px <= maxX && py >= minY && py <= maxY
    }

    /// Clamps the rect into the unit square, enforcing a minimum size.
    public func clamped(minSize: Double = 0.02) -> UnitRect {
        let w = min(max(width, minSize), 1)
        let h = min(max(height, minSize), 1)
        let nx = min(max(x, 0), 1 - w)
        let ny = min(max(y, 0), 1 - h)
        return UnitRect(x: nx, y: ny, width: w, height: h)
    }

    /// Snaps every edge to the nearest grid line. The result is at least one cell in size.
    public func snapped(columns: Int, rows: Int) -> UnitRect {
        let cols = max(columns, 1)
        let rws = max(rows, 1)
        let x0 = UnitRect.snap(minX, to: cols)
        let y0 = UnitRect.snap(minY, to: rws)
        let x1 = max(UnitRect.snap(maxX, to: cols), x0 + 1 / Double(cols))
        let y1 = max(UnitRect.snap(maxY, to: rws), y0 + 1 / Double(rws))
        return UnitRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).clamped(minSize: 0)
    }

    /// Builds the rect spanned by two arbitrary points (in any order).
    public static func spanning(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> UnitRect {
        UnitRect(x: min(ax, bx), y: min(ay, by), width: abs(bx - ax), height: abs(by - ay))
    }

    /// Rounds a unit value to the nearest multiple of `1 / divisions`.
    public static func snap(_ value: Double, to divisions: Int) -> Double {
        let n = Double(max(divisions, 1))
        return (value * n).rounded() / n
    }

    public func isApproximatelyEqual(to other: UnitRect, tolerance: Double = 0.001) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    /// A short human-readable size, e.g. "50% × 100%".
    public var sizeDescription: String {
        "\(Int((width * 100).rounded()))% × \(Int((height * 100).rounded()))%"
    }
}
