import AppKit
import SwiftUI
import MacTileCore

struct ShortcutsSettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            ForEach(SnapPreset.groups.indices, id: \.self) { index in
                Section(index == 0 ? "Snap" : "") {
                    ForEach(SnapPreset.groups[index]) { preset in
                        ShortcutRow(title: preset.title, action: .preset(preset))
                    }
                }
            }

            Section("Window") {
                ForEach(WindowAction.general, id: \.self) { action in
                    ShortcutRow(title: action.generalTitle ?? "", action: action)
                }
            }

            ForEach(state.config.layouts.filter { !$0.zones.isEmpty }) { layout in
                Section("Layout: \(layout.name)") {
                    ForEach(Array(layout.zones.enumerated()), id: \.element.id) { index, zone in
                        HStack(spacing: 10) {
                            LayoutThumbnail(layout: layout, highlighted: zone.id)
                                .frame(width: 40, height: 25)
                            ShortcutRow(title: "Zone \(index + 1)  ·  \(zone.rect.sizeDescription)",
                                        action: .zone(layoutID: layout.id, zoneID: zone.id))
                        }
                    }
                }
            }

            if !state.config.workspaces.isEmpty {
                Section("Workspaces") {
                    ForEach(state.config.workspaces) { workspace in
                        ShortcutRow(title: workspace.name, action: .workspace(workspace.id))
                    }
                }
            }

            Section {
                HStack {
                    Text("Shortcuts work system-wide. Assigning a shortcut that is already in use moves it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Default Shortcuts") {
                        state.config.bindings = HotKeyBinding.defaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutRow: View {
    @EnvironmentObject var state: AppState
    let title: String
    let action: WindowAction

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorder(combo: Binding(
                get: { state.config.combo(for: action) },
                set: { state.config.setCombo($0, for: action) }))
        }
    }
}

/// Click, then type a shortcut. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @StateObject private var recorder = KeyRecorder()

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start { result in
                        switch result {
                        case .set(let newCombo): combo = newCombo
                        case .clear: combo = nil
                        case .cancel: break
                        }
                    }
                }
            } label: {
                Text(recorder.isRecording ? "Type shortcut…" : (combo?.displayString ?? "Record Shortcut"))
                    .foregroundStyle(combo == nil && !recorder.isRecording ? Color.secondary : Color.primary)
                    .frame(minWidth: 130)
            }
            if combo != nil, !recorder.isRecording {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
            }
        }
        .onDisappear { recorder.stop() }
    }
}

/// Captures the next key press in the settings window. Global hot keys are suspended
/// while recording so the combo being typed isn't triggered instead.
final class KeyRecorder: ObservableObject {
    enum Result {
        case set(KeyCombo)
        case clear
        case cancel
    }

    @Published private(set) var isRecording = false
    private var monitor: Any?
    private var completion: ((Result) -> Void)?

    func start(completion: @escaping (Result) -> Void) {
        stop()
        self.completion = completion
        isRecording = true
        NotificationCenter.default.post(name: .shortcutRecordingDidStart, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        completion = nil
        if isRecording {
            isRecording = false
            NotificationCenter.default.post(name: .shortcutRecordingDidEnd, object: nil)
        }
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let modifiers = KeyCombo.Modifiers(event.modifierFlags)
        let result: Result
        if keyCode == KeyCodes.escape && modifiers.isEmpty {
            result = .cancel
        } else if (keyCode == KeyCodes.delete || keyCode == KeyCodes.forwardDelete) && modifiers.isEmpty {
            result = .clear
        } else if modifiers.isEmpty && !KeyCodes.functionKeys.contains(keyCode) {
            // Plain letters would hijack typing everywhere; require a modifier.
            NSSound.beep()
            return
        } else {
            result = .set(KeyCombo(keyCode: keyCode, modifiers: modifiers))
        }
        let completion = self.completion
        stop()
        completion?(result)
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if isRecording { NotificationCenter.default.post(name: .shortcutRecordingDidEnd, object: nil) }
    }
}
