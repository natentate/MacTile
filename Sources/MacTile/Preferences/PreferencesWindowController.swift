import AppKit
import SwiftUI
import MacTileCore

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    convenience init(state: AppState) {
        let root = PreferencesView()
            .environmentObject(state)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "MacTile Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 860, height: 600))
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("MacTileSettings")
        self.init(window: window)
        window.delegate = self
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // End any in-progress shortcut recording so global hot keys come back.
        window?.makeFirstResponder(nil)
    }
}

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            LayoutsSettingsView()
                .tabItem { Label("Layouts", systemImage: "rectangle.split.3x3") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            WorkspacesSettingsView()
                .tabItem { Label("Workspaces", systemImage: "square.stack.3d.up") }
            ExclusionsSettingsView()
                .tabItem { Label("Exclusions", systemImage: "nosign") }
        }
        .padding(12)
        .frame(minWidth: 740, minHeight: 500)
    }
}
