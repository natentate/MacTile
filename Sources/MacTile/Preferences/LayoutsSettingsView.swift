import SwiftUI
import MacTileCore

struct LayoutsSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: UUID? = nil

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(state.config.layouts) { layout in
                        HStack(spacing: 10) {
                            LayoutThumbnail(layout: layout)
                                .frame(width: 48, height: 30)
                            Text(layout.name).lineLimit(1)
                            Spacer()
                            if !layout.showInPanel {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(.secondary)
                                    .help("Hidden from the drag panel")
                            }
                        }
                        .padding(.vertical, 2)
                        .tag(layout.id)
                    }
                    .onMove { source, destination in
                        state.config.layouts.move(fromOffsets: source, toOffset: destination)
                    }
                }
                Divider()
                HStack(spacing: 4) {
                    Menu {
                        ForEach(TileLayout.templates.indices, id: \.self) { index in
                            Button(TileLayout.templates[index].name) { add(TileLayout.templates[index].make()) }
                        }
                        Divider()
                        Button("Duplicate Selected") {
                            if let index = state.layoutIndex(selection) {
                                add(state.config.layouts[index].duplicated())
                            }
                        }
                        .disabled(selection == nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection == nil)
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 230)

            Divider()

            if let index = state.layoutIndex(selection) {
                LayoutEditorView(layout: layoutBinding(id: state.config.layouts[index].id))
                    .id(state.config.layouts[index].id)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.split.3x3").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Select a layout to edit it, or add a new one with +.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selection == nil { selection = state.config.layouts.first?.id }
        }
    }

    /// A binding that keeps working even if the layout is deleted while the editor is visible.
    private func layoutBinding(id: UUID) -> Binding<TileLayout> {
        Binding(
            get: {
                state.config.layouts.first { $0.id == id }
                    ?? TileLayout(id: id, name: "", columns: 1, rows: 1, zones: [])
            },
            set: { newValue in
                guard let current = state.layoutIndex(id) else { return }
                state.config.layouts[current] = newValue
                state.config.pruneDanglingReferences()
            })
    }

    private func add(_ layout: TileLayout) {
        state.config.layouts.append(layout)
        selection = layout.id
    }

    private func deleteSelected() {
        guard let id = selection, let index = state.layoutIndex(id) else { return }
        state.config.removeLayout(id: id)
        let remaining = state.config.layouts
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
}

/// A small read-only picture of a layout.
struct LayoutThumbnail: View {
    let layout: TileLayout
    var highlighted: UUID?
    var showNumbers = false

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.18))
                ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                    let rect = LayoutGeometry.rect(for: zone.rect, in: bounds.insetBy(dx: 2, dy: 2), inset: 1)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(zone.id == highlighted ? Color.accentColor : Color.accentColor.opacity(0.5))
                        .overlay {
                            if showNumbers {
                                Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                            }
                        }
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
    }
}
