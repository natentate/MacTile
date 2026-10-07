import AppKit
import SwiftUI
import MacTileCore

struct ExclusionsSettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MacTile ignores windows from these apps — no drag panel, snapping or shortcuts.")
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(state.config.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        if let icon = icon(for: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(name(for: bundleID))
                        Spacer()
                        Text(bundleID).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(bundleID)
                }
            }
            .frame(minHeight: 260)

            HStack(spacing: 4) {
                Menu {
                    ForEach(RunningApps.regular().filter { !state.config.excludedBundleIDs.contains($0.bundleID) },
                            id: \.bundleID) { app in
                        Button(app.name) { state.config.excludedBundleIDs.append(app.bundleID) }
                    }
                    Divider()
                    Button("Choose Application…") {
                        if let app = RunningApps.chooseApplication(),
                           !state.config.excludedBundleIDs.contains(app.bundleID) {
                            state.config.excludedBundleIDs.append(app.bundleID)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Button {
                    state.config.excludedBundleIDs.removeAll { $0 == selection }
                    selection = nil
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                Spacer()
            }
        }
        .padding(16)
    }

    private func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func name(for bundleID: String) -> String {
        guard let url = appURL(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func icon(for bundleID: String) -> NSImage? {
        appURL(for: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
