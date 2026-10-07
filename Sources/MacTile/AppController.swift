import AppKit
import Combine
import MacTileCore

/// Owns every subsystem and routes actions from shortcuts, the menu bar and settings.
final class AppController {
    let state: AppState
    let windows: WindowManager
    let hotKeys = HotKeyController()
    private let drag: DragSnapController
    private let missionControl: MissionControlController
    private let workspaces: WorkspaceLauncher
    private let quickLayout = QuickLayoutPanel()
    private let picker = LayoutPanel(interactive: true)
    private var menu: StatusMenuController?
    private var preferences: PreferencesWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?

    init() {
        state = AppState()
        windows = WindowManager(state: state)
        drag = DragSnapController(state: state, windows: windows)
        missionControl = MissionControlController(state: state, windows: windows)
        workspaces = WorkspaceLauncher(state: state, windows: windows)
    }

    func start() {
        state.perform = { [weak self] action in self?.perform(action) }
        hotKeys.onAction = { [weak self] action in self?.perform(action) }
        hotKeys.register(state.config.bindings)
        state.$config
            .map(\.bindings)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] bindings in self?.hotKeys.register(bindings) }
            .store(in: &cancellables)

        menu = StatusMenuController(controller: self)
        drag.start()
        missionControl.start()

        picker.onCancel = { [weak self] in self?.picker.hide() }

        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.prompt()
            waitForPermission()
        }
    }

    func stop() {
        drag.stop()
        missionControl.stop()
        state.saveNow()
    }

    // MARK: Actions

    func perform(_ action: WindowAction) {
        switch action {
        case .toggleEnabled:
            state.config.isEnabled.toggle()
            return
        case .workspace(let id):
            guard requirePermission() else { return }
            workspaces.apply(workspaceID: id)
            return
        default:
            break
        }

        guard state.config.isEnabled, requirePermission() else { return }
        guard let window = windows.focusedWindow() else {
            NSSound.beep()
            return
        }

        switch action {
        case .preset(let preset):
            windows.apply(preset.rect, to: window)
        case .zone(let layoutID, let zoneID):
            guard let zone = state.config.layout(withID: layoutID)?.zone(withID: zoneID) else {
                NSSound.beep()
                return
            }
            windows.apply(zone.rect, to: window)
        case .restore:
            windows.restore(window)
        case .center:
            windows.center(window)
        case .nextDisplay:
            windows.moveToAdjacentDisplay(window, forward: true)
        case .previousDisplay:
            windows.moveToAdjacentDisplay(window, forward: false)
        case .quickLayout:
            showQuickLayout(for: window)
        case .layoutPicker:
            showLayoutPicker(for: window)
        case .toggleEnabled, .workspace:
            break
        }
    }

    private func showQuickLayout(for window: AXWindow) {
        guard let screen = windows.screen(of: window) else { return }
        let config = state.config
        quickLayout.show(
            on: screen, columns: config.quickLayoutColumns, rows: config.quickLayoutRows,
            frameForUnit: { [weak self] unit in self?.windows.frame(for: unit, on: screen) ?? .zero },
            onSelect: { [weak self] unit in self?.windows.apply(unit, to: window, on: screen) })
    }

    private func showLayoutPicker(for window: AXWindow) {
        guard let screen = windows.screen(of: window) else { return }
        let config = state.config
        picker.onPick = { [weak self] hit in
            self?.picker.hide()
            self?.windows.apply(hit.zone.rect, to: window, on: screen)
        }
        picker.show(layouts: config.panelLayouts, style: config.panelStyle, position: .center,
                    on: screen, cursor: NSEvent.mouseLocation)
    }

    // MARK: Windows

    func showPreferences() {
        if preferences == nil {
            preferences = PreferencesWindowController(state: state)
        }
        preferences?.present()
    }

    // MARK: Permission

    @discardableResult
    private func requirePermission() -> Bool {
        if AccessibilityPermission.isTrusted { return true }
        AccessibilityPermission.prompt()
        waitForPermission()
        return false
    }

    /// Polls until Accessibility access is granted, then refreshes the menu.
    private func waitForPermission() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard AccessibilityPermission.isTrusted else { return }
            timer.invalidate()
            self?.permissionTimer = nil
            self?.objectWillChangePermission()
        }
    }

    private func objectWillChangePermission() {
        state.objectWillChange.send()
    }
}
