import AppKit
import Carbon
import MacTileCore

extension Notification.Name {
    /// Posted by the shortcut recorder so global hot keys don't swallow the keys being recorded.
    static let shortcutRecordingDidStart = Notification.Name("MacTileShortcutRecordingDidStart")
    static let shortcutRecordingDidEnd = Notification.Name("MacTileShortcutRecordingDidEnd")
}

extension KeyCombo {
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

/// Registers system-wide shortcuts with Carbon's `RegisterEventHotKey`, which needs no
/// extra permission and works while another app is frontmost.
final class HotKeyController {
    var onAction: ((WindowAction) -> Void)?

    /// Bindings the system refused (usually because another app owns the combo).
    private(set) var failedBindings: [HotKeyBinding] = []

    private static let signature: OSType = 0x4D54_696C // "MTil"
    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: WindowAction] = [:]
    private var bindings: [HotKeyBinding] = []
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?
    private var suspendCount = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        installHandler()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .shortcutRecordingDidStart, object: nil, queue: .main) {
            [weak self] _ in self?.suspend()
        })
        observers.append(center.addObserver(forName: .shortcutRecordingDidEnd, object: nil, queue: .main) {
            [weak self] _ in self?.resume()
        })
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func register(_ bindings: [HotKeyBinding]) {
        self.bindings = bindings
        unregisterAll()
        failedBindings = []
        guard suspendCount == 0 else { return }

        for binding in bindings {
            let id = nextID
            nextID &+= 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: HotKeyController.signature, id: id)
            let status = RegisterEventHotKey(
                binding.combo.keyCode, binding.combo.carbonModifiers, hotKeyID,
                GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registered.append(ref)
                actions[id] = binding.action
            } else {
                failedBindings.append(binding)
            }
        }
    }

    func suspend() {
        suspendCount += 1
        unregisterAll()
    }

    func resume() {
        suspendCount = max(suspendCount - 1, 0)
        if suspendCount == 0 { register(bindings) }
    }

    private func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
        actions = [:]
    }

    fileprivate func handle(id: UInt32) {
        guard let action = actions[id] else { return }
        onAction?(action)
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
            controller.handle(id: hotKeyID.id)
            return noErr
        }, 1, &spec, context, &handler)
    }
}
