import Foundation

/// A saved arrangement: a layout plus the app that belongs in each zone.
/// Applying it launches (optionally) and places every app in one go.
public struct Workspace: Codable, Hashable, Identifiable {
    public struct Assignment: Codable, Hashable, Identifiable {
        public var id: UUID
        public var zoneID: UUID
        public var bundleID: String
        public var appName: String

        public init(id: UUID = UUID(), zoneID: UUID, bundleID: String, appName: String) {
            self.id = id
            self.zoneID = zoneID
            self.bundleID = bundleID
            self.appName = appName
        }
    }

    public var id: UUID
    public var name: String
    public var layoutID: UUID
    public var assignments: [Assignment]
    public var launchApps: Bool

    public init(
        id: UUID = UUID(), name: String, layoutID: UUID,
        assignments: [Assignment] = [], launchApps: Bool = true
    ) {
        self.id = id
        self.name = name
        self.layoutID = layoutID
        self.assignments = assignments
        self.launchApps = launchApps
    }

    public func assignment(forZone zoneID: UUID) -> Assignment? {
        assignments.first { $0.zoneID == zoneID }
    }

    /// Assigns an app to a zone, or clears the zone when `bundleID` is nil.
    public mutating func assign(zoneID: UUID, bundleID: String?, appName: String = "") {
        assignments.removeAll { $0.zoneID == zoneID }
        if let bundleID, !bundleID.isEmpty {
            assignments.append(Assignment(zoneID: zoneID, bundleID: bundleID, appName: appName))
        }
    }
}
