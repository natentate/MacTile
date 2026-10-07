import AppKit
import MacTileCore

/// The menu bar item. The menu is rebuilt each time it opens so it always reflects the
/// current layouts, workspaces and shortcuts.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private final class ActionBox: NSObject {
        let action: WindowAction
        init(_ action: WindowAction) { self.action = action }
    }

    private unowned let controller: AppController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(controller: AppController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "MacTile")
            image?.isTemplate = true
            button.image = image
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        let config = controller.state.config

        if !AccessibilityPermission.isTrusted {
            let warning = NSMenuItem(title: "Grant Accessibility Access…",
                                     action: #selector(openAccessibility), keyEquivalent: "")
            warning.target = self
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let enabled = NSMenuItem(title: config.isEnabled ? "MacTile Enabled" : "MacTile Paused",
                                 action: #selector(performAction(_:)), keyEquivalent: "")
        enabled.state = config.isEnabled ? .on : .off
        configure(enabled, action: .toggleEnabled, config: config)
        menu.addItem(enabled)
        menu.addItem(.separator())

        for (index, group) in SnapPreset.groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for preset in group {
                menu.addItem(actionItem(preset.title, .preset(preset), config: config))
            }
        }
        menu.addItem(.separator())

        let layoutsItem = NSMenuItem(title: "Layouts", action: nil, keyEquivalent: "")
        let layoutsMenu = NSMenu()
        for layout in config.layouts where !layout.zones.isEmpty {
            let item = NSMenuItem(title: layout.name, action: nil, keyEquivalent: "")
            let zonesMenu = NSMenu()
            for (index, zone) in layout.zones.enumerated() {
                let title = "Zone \(index + 1)  (\(zone.rect.sizeDescription))"
                zonesMenu.addItem(actionItem(title, .zone(layoutID: layout.id, zoneID: zone.id), config: config))
            }
            item.submenu = zonesMenu
            layoutsMenu.addItem(item)
        }
        layoutsItem.submenu = layoutsMenu
        menu.addItem(layoutsItem)

        if !config.workspaces.isEmpty {
            let workspacesItem = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
            let workspacesMenu = NSMenu()
            for workspace in config.workspaces {
                workspacesMenu.addItem(actionItem(workspace.name, .workspace(workspace.id), config: config))
            }
            workspacesItem.submenu = workspacesMenu
            menu.addItem(workspacesItem)
        }

        menu.addItem(.separator())
        for action in [WindowAction.quickLayout, .layoutPicker, .center, .restore, .nextDisplay, .previousDisplay] {
            menu.addItem(actionItem(action.generalTitle ?? "", action, config: config))
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit MacTile", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func actionItem(_ title: String, _ action: WindowAction, config: Configuration) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        configure(item, action: action, config: config)
        return item
    }

    private func configure(_ item: NSMenuItem, action: WindowAction, config: Configuration) {
        item.target = self
        item.representedObject = ActionBox(action)
        if let combo = config.combo(for: action), let key = combo.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = combo.modifiers.eventFlags
        }
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        // Let the menu close and focus settle on the target app before acting.
        DispatchQueue.main.async { [controller] in controller.perform(box.action) }
    }

    @objc private func openSettings() {
        controller.showPreferences()
    }

    @objc private func openAccessibility() {
        AccessibilityPermission.prompt()
        AccessibilityPermission.openSettings()
    }
}
