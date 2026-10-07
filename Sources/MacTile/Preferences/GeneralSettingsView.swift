import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import MacTileCore

struct GeneralSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String? = nil
    @State private var isTrusted = AccessibilityPermission.isTrusted

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable MacTile", isOn: $state.config.isEnabled)
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Image(systemName: isTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isTrusted ? Color.green : Color.orange)
                    Text(isTrusted ? "Accessibility access granted" : "Accessibility access is required to move windows")
                    Spacer()
                    if !isTrusted {
                        Button("Open Settings…") {
                            AccessibilityPermission.prompt()
                            AccessibilityPermission.openSettings()
                        }
                    }
                }
            }

            Section("Drag & Drop Panel") {
                Picker("Show layout panel", selection: $state.config.panelTrigger) {
                    ForEach(PanelTrigger.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if state.config.panelTrigger == .modifier {
                    modifierPicker("Modifier key", selection: $state.config.panelModifier)
                }
                Picker("Layout view", selection: $state.config.panelStyle) {
                    ForEach(PanelStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Panel position", selection: $state.config.panelPosition) {
                    ForEach(PanelPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Drag any window and drop it onto a zone in the panel to resize and position it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Snapping") {
                Toggle("Snap to screen edges and corners", isOn: $state.config.edgeSnapping)
                Toggle("Show zone overlay while dragging with a modifier", isOn: $state.config.zoneOverlayEnabled)
                if state.config.zoneOverlayEnabled {
                    modifierPicker("Overlay modifier", selection: $state.config.zoneOverlayModifier)
                }
                Toggle("Restore original size when dragging a window out of a zone",
                       isOn: $state.config.restoreOnUnsnap)
                HStack {
                    Text("Window gap")
                    Slider(value: $state.config.gap, in: 0...40, step: 2)
                    Text("\(Int(state.config.gap)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }

            Section("Zone Overlay Layout per Display") {
                Picker("Default", selection: $state.config.defaultLayoutID) {
                    Text("First layout").tag(UUID?.none)
                    ForEach(state.config.layouts) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                ForEach(NSScreen.screens, id: \.displayKey) { screen in
                    Picker(screen.localizedName, selection: displayBinding(screen.displayKey)) {
                        Text("Use default").tag(UUID?.none)
                        ForEach(state.config.layouts) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
            }

            Section("Quick Layout Grid") {
                Stepper("Columns: \(state.config.quickLayoutColumns)",
                        value: $state.config.quickLayoutColumns, in: 2...16)
                Stepper("Rows: \(state.config.quickLayoutRows)", value: $state.config.quickLayoutRows, in: 2...12)
            }

            Section("Configuration") {
                HStack {
                    Button("Export…", action: exportConfig)
                    Button("Import…", action: importConfig)
                    Button("Show in Finder") {
                        state.saveNow()
                        NSWorkspace.shared.activateFileViewerSelecting([state.store.url])
                    }
                    Spacer()
                    Button("Reset to Defaults", role: .destructive, action: resetConfig)
                }
                if let error = state.lastSaveError {
                    Text("Couldn't save settings: \(error)").font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            isTrusted = AccessibilityPermission.isTrusted
        }
    }

    private func modifierPicker(_ title: String, selection: Binding<DragModifier>) -> some View {
        Picker(title, selection: selection) {
            ForEach(DragModifier.allCases, id: \.self) { Text($0.title).tag($0) }
        }
    }

    private func displayBinding(_ key: String) -> Binding<UUID?> {
        Binding(
            get: { state.config.displayLayouts[key] },
            set: { state.config.displayLayouts[key] = $0 })
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription). "
                + "Launch at login requires running MacTile.app from the Applications folder."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MacTile Configuration.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigStore.encode(state.config).write(to: url, options: .atomic)
        } catch {
            showError("Export failed", error)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            state.config = try ConfigStore.decode(Data(contentsOf: url))
        } catch {
            showError("Import failed", error)
        }
    }

    private func resetConfig() {
        let alert = NSAlert()
        alert.messageText = "Reset all MacTile settings?"
        alert.informativeText = "Your layouts, shortcuts and workspaces will be replaced with the defaults."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            state.config = Configuration()
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
