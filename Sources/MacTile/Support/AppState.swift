import AppKit
import Combine
import MacTileCore

/// The live configuration shared by the app and the settings UI. Every change is
/// saved (debounced) to disk.
final class AppState: ObservableObject {
    @Published var config: Configuration {
        didSet { scheduleSave() }
    }

    /// Set by `AppController` so views can trigger actions (e.g. "Apply workspace now").
    var perform: ((WindowAction) -> Void)?

    let store: ConfigStore
    @Published private(set) var lastSaveError: String?
    private var pendingSave: DispatchWorkItem?

    init(store: ConfigStore = ConfigStore()) {
        self.store = store
        self.config = store.load()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try store.save(config)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    /// A binding-friendly accessor for one layout that tolerates the layout disappearing.
    func layoutIndex(_ id: UUID?) -> Int? {
        guard let id else { return nil }
        return config.layouts.firstIndex { $0.id == id }
    }

    func workspaceIndex(_ id: UUID?) -> Int? {
        guard let id else { return nil }
        return config.workspaces.firstIndex { $0.id == id }
    }
}
