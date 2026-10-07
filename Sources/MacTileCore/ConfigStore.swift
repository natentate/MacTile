import Foundation

/// Reads and writes `Configuration` as pretty-printed JSON.
public final class ConfigStore {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    /// `~/Library/Application Support/MacTile/config.json`
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MacTile", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    /// Loads the configuration. A missing file yields defaults; an unreadable one is
    /// moved aside (so it is never silently overwritten) and defaults are returned.
    public func load() -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        do {
            return try ConfigStore.decode(Data(contentsOf: url))
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent().appendingPathComponent("config.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return Configuration()
        }
    }

    public func save(_ configuration: Configuration) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ConfigStore.encode(configuration).write(to: url, options: .atomic)
    }

    public static func encode(_ configuration: Configuration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configuration)
    }

    public static func decode(_ data: Data) throws -> Configuration {
        var configuration = try JSONDecoder().decode(Configuration.self, from: data)
        configuration.pruneDanglingReferences()
        return configuration
    }
}
