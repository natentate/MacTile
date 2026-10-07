import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Mission Control draws window thumbnails itself and only exposes each one's title and
/// on-screen rect through Accessibility. These helpers map a thumbnail back to the real
/// window it represents.
public enum ThumbnailMatcher {
    public struct Candidate: Equatable {
        public var title: String
        public var appName: String
        public var bundleID: String?
        /// Width / height of the real window.
        public var aspect: Double

        public init(title: String, appName: String, bundleID: String?, aspect: Double) {
            self.title = title
            self.appName = appName
            self.bundleID = bundleID
            self.aspect = aspect
        }
    }

    /// How well a thumbnail title matches a window title. Higher is better; 0 is no match.
    /// Mission Control truncates long titles with "…", at the end or in the middle.
    public static func titleScore(thumbnail: String, window: String, appName: String = "") -> Int {
        let thumb = thumbnail.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = window.trimmingCharacters(in: .whitespacesAndNewlines)

        if thumb.isEmpty || title.isEmpty {
            // Untitled windows: Mission Control shows nothing or the app name.
            if title.isEmpty && (thumb.isEmpty || thumb == appName) { return 1 }
            return 0
        }
        if thumb == title { return 4 }

        for ellipsis in ["…", "..."] {
            if let range = thumb.range(of: ellipsis) {
                let prefix = String(thumb[thumb.startIndex..<range.lowerBound])
                let suffix = String(thumb[range.upperBound...])
                if title.count >= prefix.count + suffix.count, title.hasPrefix(prefix), title.hasSuffix(suffix),
                   !(prefix.isEmpty && suffix.isEmpty) {
                    return 3
                }
            }
        }
        if title.hasPrefix(thumb) || thumb.hasPrefix(title) { return 2 }
        if !appName.isEmpty, thumb == appName { return 1 }
        return 0
    }

    /// The index of the candidate a thumbnail most likely shows, or nil when none match.
    /// Ties on title are broken by how closely the window's shape matches the thumbnail's.
    public static func bestMatch(
        thumbnailTitle: String, thumbnailAspect: Double, bundleID: String? = nil, candidates: [Candidate]
    ) -> Int? {
        var best: (index: Int, score: Int, shape: Double)?
        for (index, candidate) in candidates.enumerated() {
            if let bundleID, let other = candidate.bundleID, bundleID != other { continue }
            let score = titleScore(thumbnail: thumbnailTitle, window: candidate.title, appName: candidate.appName)
            guard score > 0 else { continue }
            let shape = abs(log(max(candidate.aspect, 0.01)) - log(max(thumbnailAspect, 0.01)))
            if let current = best, score < current.score || (score == current.score && shape >= current.shape) {
                continue
            }
            best = (index, score, shape)
        }
        return best?.index
    }
}

public enum MissionControlIdentifier {
    /// On macOS 27 thumbnails are identified as `<bundle id>.space.<space id>`.
    public static func bundleID(from identifier: String?) -> String? {
        guard let identifier, let range = identifier.range(of: ".space.", options: .backwards) else { return nil }
        let bundle = String(identifier[identifier.startIndex..<range.lowerBound])
        return bundle.isEmpty ? nil : bundle
    }
}

public enum ReadingOrder {
    /// Indices of `frames` sorted into rows (top to bottom), then left to right within a row.
    /// Frames whose vertical centres are within `rowTolerance` of a row's first frame share that row.
    public static func sorted(_ frames: [CGRect], rowTolerance: CGFloat = 40) -> [Int] {
        let byTop = frames.indices.sorted { frames[$0].midY < frames[$1].midY }
        var rows: [[Int]] = []
        for index in byTop {
            if let anchor = rows.last?.first, abs(frames[index].midY - frames[anchor].midY) <= rowTolerance {
                rows[rows.count - 1].append(index)
            } else {
                rows.append([index])
            }
        }
        return rows.flatMap { row in row.sorted { frames[$0].minX < frames[$1].minX } }
    }
}
