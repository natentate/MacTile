import AppKit
import SwiftUI
import MacTileCore

/// Edits one layout: name, snapping grid, and its zones on a canvas.
struct LayoutEditorView: View {
    @Binding var layout: TileLayout
    @State private var selectedZone: UUID? = nil

    private var aspect: CGFloat {
        guard let screen = NSScreen.main else { return 16 / 10 }
        return screen.visibleFrame.width / max(screen.visibleFrame.height, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Layout name", text: $layout.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Spacer()
                Toggle("Show in drag panel", isOn: $layout.showInPanel)
            }

            HStack(spacing: 16) {
                Stepper("Grid columns: \(layout.columns)", value: $layout.columns, in: 1...24)
                Stepper("Grid rows: \(layout.rows)", value: $layout.rows, in: 1...24)
                Spacer()
                Button("Fill Grid") {
                    layout.zones = TileLayout.gridZones(columns: layout.columns, rows: layout.rows)
                    selectedZone = nil
                }
                .help("Replace the zones with one zone per grid cell")
                Button("Clear") {
                    layout.zones = []
                    selectedZone = nil
                }
            }

            LayoutCanvas(layout: $layout, selection: $selectedZone)
                .aspectRatio(aspect, contentMode: .fit)
                .frame(maxWidth: .infinity)

            HStack {
                Button("Split Left | Right") { split(.leftRight) }
                    .disabled(selectedZone == nil)
                Button("Split Top / Bottom") { split(.topBottom) }
                    .disabled(selectedZone == nil)
                Button("Delete Zone", role: .destructive) {
                    layout.zones.removeAll { $0.id == selectedZone }
                    selectedZone = nil
                }
                .disabled(selectedZone == nil)
                Spacer()
                if let id = selectedZone, let index = layout.index(ofZone: id) {
                    Text("Zone \(index + 1): \(layout.zones[index].rect.sizeDescription)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Text("Drag on empty space to draw a zone. Drag a zone to move it, or its corner handle to resize. "
                 + "Zones snap to the grid; overlapping zones are allowed — the smallest one wins on drop.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private func split(_ axis: TileLayout.SplitAxis) {
        guard let id = selectedZone else { return }
        layout.split(zoneID: id, axis: axis)
    }
}

/// The interactive drawing surface of the layout editor.
struct LayoutCanvas: View {
    @Binding var layout: TileLayout
    @Binding var selection: UUID?
    @State private var interaction: Interaction? = nil

    enum Mode {
        case create(startX: Double, startY: Double)
        case move(id: UUID, original: UnitRect)
        case resize(id: UUID, original: UnitRect)
    }

    struct Interaction {
        var mode: Mode
        var draft: UnitRect?
    }

    let handleSize: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let bounds = CGRect(origin: .zero, size: size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                GridLines(columns: layout.columns, rows: layout.rows)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)

                ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                    let rect = LayoutGeometry.rect(for: zone.rect, in: bounds, inset: 3)
                    ZoneTile(number: index + 1, isSelected: zone.id == selection, handleSize: handleSize)
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .offset(x: rect.minX, y: rect.minY)
                }

                if let interaction, case .create = interaction.mode, let draft = interaction.draft {
                    let rect = LayoutGeometry.rect(for: draft, in: bounds, inset: 3)
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in dragChanged(value, size: size) }
                    .onEnded { value in dragEnded(value, size: size) }
            )
        }
    }

    // MARK: Gesture

    private func unit(_ point: CGPoint, _ size: CGSize) -> (x: Double, y: Double) {
        (Double(point.x / max(size.width, 1)), Double(point.y / max(size.height, 1)))
    }

    private func dragChanged(_ value: DragGesture.Value, size: CGSize) {
        if interaction == nil {
            interaction = Interaction(mode: beginMode(at: value.startLocation, size: size), draft: nil)
        }
        guard var current = interaction else { return }
        let dx = Double(value.translation.width / max(size.width, 1))
        let dy = Double(value.translation.height / max(size.height, 1))

        switch current.mode {
        case .create(let startX, let startY):
            let end = unit(value.location, size)
            current.draft = UnitRect.spanning(startX, startY, min(max(end.x, 0), 1), min(max(end.y, 0), 1))
                .snapped(columns: layout.columns, rows: layout.rows)
        case .move(let id, let original):
            guard let index = layout.index(ofZone: id) else { return }
            var moved = original
            moved.x = UnitRect.snap(original.x + dx, to: layout.columns)
            moved.y = UnitRect.snap(original.y + dy, to: layout.rows)
            layout.zones[index].rect = moved.clamped(minSize: 0)
        case .resize(let id, let original):
            guard let index = layout.index(ofZone: id) else { return }
            let minW = 1 / Double(layout.columns)
            let minH = 1 / Double(layout.rows)
            let maxX = min(max(UnitRect.snap(original.maxX + dx, to: layout.columns), original.x + minW), 1)
            let maxY = min(max(UnitRect.snap(original.maxY + dy, to: layout.rows), original.y + minH), 1)
            layout.zones[index].rect = UnitRect(x: original.x, y: original.y,
                                                width: maxX - original.x, height: maxY - original.y)
        }
        interaction = current
    }

    private func dragEnded(_ value: DragGesture.Value, size: CGSize) {
        defer { interaction = nil }
        guard let interaction else { return }
        let distance = hypot(value.translation.width, value.translation.height)
        if case .create = interaction.mode {
            if distance > 4, let draft = interaction.draft, draft.area > 0 {
                let zone = Zone(rect: draft)
                layout.zones.append(zone)
                selection = zone.id
            } else {
                selection = nil
            }
        }
    }

    private func beginMode(at point: CGPoint, size: CGSize) -> Mode {
        let bounds = CGRect(origin: .zero, size: size)
        // Resize handle of the selected zone takes priority.
        if let id = selection, let zone = layout.zone(withID: id) {
            let rect = LayoutGeometry.rect(for: zone.rect, in: bounds, inset: 3)
            let handle = CGRect(x: rect.maxX - handleSize - 4, y: rect.maxY - handleSize - 4,
                                width: handleSize + 8, height: handleSize + 8)
            if handle.contains(point) { return .resize(id: id, original: zone.rect) }
        }
        let u = unit(point, size)
        if let zone = layout.zone(atX: u.x, y: u.y) {
            selection = zone.id
            return .move(id: zone.id, original: zone.rect)
        }
        selection = nil
        let start = (UnitRect.snap(u.x, to: layout.columns), UnitRect.snap(u.y, to: layout.rows))
        return .create(startX: start.0, startY: start.1)
    }
}

private struct ZoneTile: View {
    let number: Int
    let isSelected: Bool
    let handleSize: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isSelected ? 0.55 : 0.3))
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : Color.accentColor.opacity(0.6),
                              lineWidth: isSelected ? 2 : 1)
            Text("\(number)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isSelected {
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: handleSize, height: handleSize)
                    .background(Circle().fill(Color.accentColor))
                    .padding(4)
            }
        }
    }
}

private struct GridLines: Shape {
    let columns: Int
    let rows: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if columns > 1 {
            for column in 1..<columns {
                let x = rect.minX + rect.width * CGFloat(column) / CGFloat(columns)
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }
        if rows > 1 {
            for row in 1..<rows {
                let y = rect.minY + rect.height * CGFloat(row) / CGFloat(rows)
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        return path
    }
}
