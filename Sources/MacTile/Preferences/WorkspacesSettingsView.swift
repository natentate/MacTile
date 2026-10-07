import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MacTileCore

struct WorkspacesSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: UUID? = nil

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(state.config.workspaces) { workspace in
                        Label(workspace.name, systemImage: "square.stack.3d.up").tag(workspace.id)
                    }
                    .onMove { state.config.workspaces.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 4) {
                    Button(action: add) { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .disabled(state.config.layouts.isEmpty)
                    Button(action: deleteSelected) { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                        .disabled(selection == nil)
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 230)

            Divider()

            if let id = selection, state.workspaceIndex(id) != nil {
                WorkspaceEditor(workspace: workspaceBinding(id))
                    .id(id)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("A workspace puts specific apps into the zones of a layout with one shortcut.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selection == nil { selection = state.config.workspaces.first?.id }
        }
    }

    private func workspaceBinding(_ id: UUID) -> Binding<Workspace> {
        Binding(
            get: {
                state.config.workspaces.first { $0.id == id }
                    ?? Workspace(id: id, name: "", layoutID: state.config.layouts.first?.id ?? UUID())
            },
            set: { newValue in
                guard let index = state.workspaceIndex(id) else { return }
                state.config.workspaces[index] = newValue
            })
    }

    private func add() {
        guard let layout = state.config.layouts.first(where: { !$0.zones.isEmpty }) ?? state.config.layouts.first else {
            return
        }
        let workspace = Workspace(name: "Workspace \(state.config.workspaces.count + 1)", layoutID: layout.id)
        state.config.workspaces.append(workspace)
        selection = workspace.id
    }

    private func deleteSelected() {
        guard let id = selection, let index = state.workspaceIndex(id) else { return }
        state.config.workspaces.remove(at: index)
        state.config.pruneDanglingReferences()
        let remaining = state.config.workspaces
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
}

private struct WorkspaceEditor: View {
    @EnvironmentObject var state: AppState
    @Binding var workspace: Workspace

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $workspace.name)
                Picker("Layout", selection: $workspace.layoutID) {
                    ForEach(state.config.layouts) { Text($0.name).tag($0.id) }
                }
                Toggle("Launch apps that aren't running", isOn: $workspace.launchApps)
            }

            if let layout = state.config.layout(withID: workspace.layoutID) {
                Section("Apps") {
                    LayoutThumbnail(layout: layout, showNumbers: true)
                        .frame(width: 200, height: 125)
                        .frame(maxWidth: .infinity)
                    ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                        HStack {
                            Text("Zone \(index + 1)")
                            Text(zone.rect.sizeDescription).foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            AppPicker(assignment: workspace.assignment(forZone: zone.id)) { bundleID, name in
                                workspace.assign(zoneID: zone.id, bundleID: bundleID, appName: name)
                            }
                        }
                    }
                }
            }

            Section {
                HStack {
                    Text("Apps are placed on the display under the pointer.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply Now") {
                        state.perform?(.workspace(workspace.id))
                    }
                    .disabled(workspace.assignments.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Chooses an app from those running, or any app on disk.
struct AppPicker: View {
    let assignment: Workspace.Assignment?
    let onChange: (String?, String) -> Void

    var body: some View {
        Menu {
            Button("None") { onChange(nil, "") }
            Divider()
            ForEach(RunningApps.regular(), id: \.bundleID) { app in
                Button(app.name) { onChange(app.bundleID, app.name) }
            }
            Divider()
            Button("Choose Application…") {
                if let app = RunningApps.chooseApplication() { onChange(app.bundleID, app.name) }
            }
        } label: {
            Text(assignment.map { $0.appName.isEmpty ? $0.bundleID : $0.appName } ?? "None")
        }
        .fixedSize()
    }
}

enum RunningApps {
    struct App {
        let bundleID: String
        let name: String
    }

    /// Regular (Dock-visible) apps, excluding MacTile itself, sorted by name.
    static func regular() -> [App] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> App? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else {
                    return nil
                }
                return App(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Lets the user pick any application bundle on disk.
    static func chooseApplication() -> App? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return App(bundleID: bundleID, name: name)
    }
}
