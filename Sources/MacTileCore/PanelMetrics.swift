import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Lays out layout thumbnails inside the drag panel. Coordinates are top-left origin,
/// relative to the panel.
public struct PanelMetrics: Equatable {
    public let style: PanelStyle
    public let count: Int
    public let thumbnailSize: CGSize
    public let labelHeight: CGFloat
    public let labelWidth: CGFloat
    public let padding: CGFloat
    public let spacing: CGFloat
    public let perRow: Int

    public static func make(style: PanelStyle, count: Int, aspect: CGFloat) -> PanelMetrics {
        let ratio = min(max(aspect, 0.5), 3.5)
        switch style {
        case .large:
            let width: CGFloat = 168
            return PanelMetrics(style: style, count: count,
                                thumbnailSize: CGSize(width: width, height: (width / ratio).rounded()),
                                labelHeight: 20, labelWidth: 0, padding: 16, spacing: 14, perRow: 5)
        case .compact:
            let width: CGFloat = 104
            return PanelMetrics(style: style, count: count,
                                thumbnailSize: CGSize(width: width, height: (width / ratio).rounded()),
                                labelHeight: 0, labelWidth: 0, padding: 12, spacing: 10, perRow: 8)
        case .list:
            let width: CGFloat = 96
            return PanelMetrics(style: style, count: count,
                                thumbnailSize: CGSize(width: width, height: (width / ratio).rounded()),
                                labelHeight: 0, labelWidth: 150, padding: 12, spacing: 8, perRow: 1)
        }
    }

    public var rows: Int {
        guard count > 0 else { return 0 }
        return (count + perRow - 1) / perRow
    }

    public var columns: Int { min(max(count, 1), perRow) }

    /// The footprint of one entry (thumbnail plus label).
    public var cellSize: CGSize {
        CGSize(width: thumbnailSize.width + (labelWidth > 0 ? labelWidth + 10 : 0),
               height: thumbnailSize.height + labelHeight)
    }

    public var panelSize: CGSize {
        let r = CGFloat(max(rows, 1))
        let c = CGFloat(columns)
        return CGSize(
            width: padding * 2 + c * cellSize.width + (c - 1) * spacing,
            height: padding * 2 + r * cellSize.height + (r - 1) * spacing
        )
    }

    public func cellOrigin(at index: Int) -> CGPoint {
        let row = index / perRow
        let column = index % perRow
        return CGPoint(
            x: padding + CGFloat(column) * (cellSize.width + spacing),
            y: padding + CGFloat(row) * (cellSize.height + spacing)
        )
    }

    public func thumbnailFrame(at index: Int) -> CGRect {
        CGRect(origin: cellOrigin(at: index), size: thumbnailSize)
    }

    public func labelFrame(at index: Int) -> CGRect? {
        let origin = cellOrigin(at: index)
        if labelHeight > 0 {
            return CGRect(x: origin.x, y: origin.y + thumbnailSize.height + 2,
                          width: thumbnailSize.width, height: labelHeight - 2)
        }
        if labelWidth > 0 {
            return CGRect(x: origin.x + thumbnailSize.width + 10, y: origin.y,
                          width: labelWidth, height: thumbnailSize.height)
        }
        return nil
    }

    /// The index of the thumbnail under a point, if any.
    public func thumbnailIndex(at point: CGPoint) -> Int? {
        for index in 0..<count where thumbnailFrame(at: index).contains(point) {
            return index
        }
        return nil
    }
}
