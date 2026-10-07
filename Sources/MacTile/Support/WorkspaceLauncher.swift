import AppKit
import MacTileCore

/// Applies a workspace: optionally launches each assigned app, waits for its window,
/// and places it in its zone on the display under the pointer.
final class WorkspaceLauncher {
    private let state: AppState
    private let windows: WindowManager
    private let pollInterval: TimeInterval = 0.5
    private let maxAttempts = 24

    init(state: AppState, windows: WindowManager) {
        self.state = state
        self.windows = windows
    }

    func apply(workspaceID: UUID) {
        let config = state.config
        guard let workspace = config.workspaces.first(where: { $0.id == workspaceID }),
              let layout = config.layout(withID: workspace.layoutID),
              let screen = ScreenGeometry.screen(containing: NSEvent.mouseLocation) ?? NSScreen.main else {
            NSSound.beep()
            return
        }
        for assignment in workspace.assignments {
            guard let zone = layout.zone(withID: assignment.zoneID) else { continue }
            place(bundleID: assignment.bundleID, unit: zone.rect, screen: screen,
                  launch: workspace.launchApps, attempt: 0)
        }
    }

    private func place(bundleID: String, unit: UnitRect, screen: NSScreen, launch: Bool, attempt: Int) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            if app.isHidden { app.unhide() }
            if let window = AXWindow.mainWindow(of: app.processIdentifier), window.isManageable {
                windows.apply(unit, to: window, on: screen)
                window.raise()
                return
            }
        } else if attempt == 0 {
            guard launch, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        }

        guard attempt < maxAttempts else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { [weak self] in
            self?.place(bundleID: bundleID, unit: unit, screen: screen, launch: launch, attempt: attempt + 1)
        }
    }
}
