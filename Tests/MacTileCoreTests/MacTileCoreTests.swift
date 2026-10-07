import XCTest
@testable import MacTileCore

final class UnitRectTests: XCTestCase {
    func testSnappedRoundsEdgesToGrid() {
        let rect = UnitRect(x: 0.12, y: 0.26, width: 0.4, height: 0.5).snapped(columns: 4, rows: 4)
        XCTAssertTrue(rect.isApproximatelyEqual(to: UnitRect(x: 0, y: 0.25, width: 0.5, height: 0.5)))
    }

    func testSnappedKeepsAtLeastOneCell() {
        let rect = UnitRect(x: 0.5, y: 0.5, width: 0.01, height: 0.01).snapped(columns: 4, rows: 2)
        XCTAssertEqual(rect.width, 0.25, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.5, accuracy: 0.0001)
    }

    func testClampedStaysInsideUnitSquare() {
        let rect = UnitRect(x: 0.8, y: -0.2, width: 0.5, height: 0.5).clamped()
        XCTAssertEqual(rect.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.0001)
    }

    func testSpanningOrdersPoints() {
        let rect = UnitRect.spanning(0.75, 0.5, 0.25, 0)
        XCTAssertTrue(rect.isApproximatelyEqual(to: UnitRect(x: 0.25, y: 0, width: 0.5, height: 0.5)))
    }
}

final class LayoutTests: XCTestCase {
    func testGridBuildsOneZonePerCell() {
        let layout = TileLayout.grid(name: "Six", columns: 3, rows: 2)
        XCTAssertEqual(layout.zones.count, 6)
        XCTAssertTrue(layout.zones[4].rect.isApproximatelyEqual(
            to: UnitRect(x: 1.0 / 3, y: 0.5, width: 1.0 / 3, height: 0.5)))
    }

    func testHitTestPrefersSmallestOverlappingZone() {
        let big = Zone(rect: .full)
        let small = Zone(rect: UnitRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let layout = TileLayout(name: "Nested", columns: 4, rows: 4, zones: [big, small])
        XCTAssertEqual(layout.zone(atX: 0.5, y: 0.5)?.id, small.id)
        XCTAssertEqual(layout.zone(atX: 0.1, y: 0.1)?.id, big.id)
        XCTAssertNil(TileLayout(name: "Empty", columns: 1, rows: 1, zones: []).zone(atX: 0.5, y: 0.5))
    }

    func testSplitKeepsIdentityOfFirstHalf() {
        var layout = TileLayout.grid(name: "One", columns: 1, rows: 1)
        let original = layout.zones[0].id
        let newID = layout.split(zoneID: original, axis: .leftRight)
        XCTAssertEqual(layout.zones.count, 2)
        XCTAssertEqual(layout.zones[0].id, original)
        XCTAssertEqual(layout.zones[1].id, newID)
        XCTAssertEqual(layout.zones[0].rect.width, 0.5, accuracy: 0.0001)
        XCTAssertEqual(layout.zones[1].rect.x, 0.5, accuracy: 0.0001)

        layout.split(zoneID: original, axis: .topBottom)
        XCTAssertEqual(layout.zones.count, 3)
        XCTAssertEqual(layout.zones[0].rect.height, 0.5, accuracy: 0.0001)
    }

    func testDuplicateGetsFreshIdentifiers() {
        let layout = TileLayout.grid(name: "Halves", columns: 2, rows: 1)
        let copy = layout.duplicated()
        XCTAssertNotEqual(copy.id, layout.id)
        XCTAssertEqual(copy.name, "Halves Copy")
        XCTAssertTrue(Set(copy.zones.map(\.id)).isDisjoint(with: layout.zones.map(\.id)))
        XCTAssertEqual(copy.zones.map(\.rect), layout.zones.map(\.rect))
    }

    func testDefaultLayoutsAreValid() {
        for layout in TileLayout.defaultLayouts() {
            XCTAssertFalse(layout.zones.isEmpty, layout.name)
            for zone in layout.zones {
                XCTAssertGreaterThanOrEqual(zone.rect.minX, -0.0001, layout.name)
                XCTAssertLessThanOrEqual(zone.rect.maxX, 1.0001, layout.name)
                XCTAssertLessThanOrEqual(zone.rect.maxY, 1.0001, layout.name)
            }
        }
    }
}

final class GeometryTests: XCTestCase {
    let area = CGRect(x: 0, y: 25, width: 1000, height: 800)

    func testFrameWithoutGap() {
        let frame = LayoutGeometry.frame(for: SnapPreset.rightHalf.rect, in: area)
        XCTAssertEqual(frame, CGRect(x: 500, y: 25, width: 500, height: 800))
    }

    func testGapIsFullAtEdgesAndHalvedBetweenZones() {
        let left = LayoutGeometry.frame(for: SnapPreset.leftHalf.rect, in: area, gap: 10)
        let right = LayoutGeometry.frame(for: SnapPreset.rightHalf.rect, in: area, gap: 10)
        XCTAssertEqual(left, CGRect(x: 10, y: 35, width: 485, height: 780))
        XCTAssertEqual(right, CGRect(x: 505, y: 35, width: 485, height: 780))
        // Exactly one gap between the two windows.
        XCTAssertEqual(right.minX - left.maxX, 10)
    }

    func testUnitRectRoundTrip() {
        let unit = UnitRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let frame = LayoutGeometry.frame(for: unit, in: area)
        XCTAssertTrue(LayoutGeometry.unitRect(for: frame, in: area).isApproximatelyEqual(to: unit))
    }

    func testClampMovesRectInside() {
        let clamped = LayoutGeometry.clamp(CGRect(x: 950, y: -10, width: 100, height: 100),
                                           into: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(clamped, CGRect(x: 900, y: 0, width: 100, height: 100))
    }
}

final class EdgeSnapTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testEdges() {
        XCTAssertEqual(EdgeSnap.preset(for: CGPoint(x: 0, y: 450), screenFrame: screen), .leftHalf)
        XCTAssertEqual(EdgeSnap.preset(for: CGPoint(x: 1439, y: 450), screenFrame: screen), .rightHalf)
        XCTAssertEqual(EdgeSnap.preset(for: CGPoint(x: 720, y: 0), screenFrame: screen), .maximize)
        XCTAssertNil(EdgeSnap.preset(for: CGPoint(x: 720, y: 450), screenFrame: screen))
        XCTAssertNil(EdgeSnap.preset(for: CGPoint(x: 720, y: 899), screenFrame: screen))
    }

    func testCorners() {
        XCTAssertEqual(EdgeSnap.preset(for: CGPoint(x: 0, y: 10), screenFrame: screen), .topLeft)
        XCTAssertEqual(EdgeSnap.preset(for: CGPoint(x: 1440, y: 890), screenFrame: screen), .bottomRight)
        XCTAssertEqual(EdgeSnap.preset(for: CGPoint(x: 1400, y: 0), screenFrame: screen), .topRight)
        XCTAssertEqual(EdgeSnap.preset(for: CGPoint(x: 30, y: 900), screenFrame: screen), .bottomLeft)
    }

    func testTopCanBeReserved() {
        XCTAssertNil(EdgeSnap.preset(for: CGPoint(x: 720, y: 0), screenFrame: screen, allowTop: false))
        XCTAssertNil(EdgeSnap.preset(for: CGPoint(x: 40, y: 0), screenFrame: screen, allowTop: false))
    }

    func testWorksOnSecondaryDisplays() {
        let secondary = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(EdgeSnap.preset(for: CGPoint(x: 3359, y: 300), screenFrame: secondary), .rightHalf)
    }
}

final class QuickLayoutTests: XCTestCase {
    func testCellLookupClampsToGrid() {
        XCTAssertEqual(QuickLayoutGrid.cell(atX: 0.99, y: 0.01, columns: 4, rows: 3),
                       QuickLayoutGrid.Cell(column: 3, row: 0))
        XCTAssertEqual(QuickLayoutGrid.cell(atX: 1.5, y: -1, columns: 4, rows: 3),
                       QuickLayoutGrid.Cell(column: 3, row: 0))
    }

    func testSelectionInAnyDirection() {
        let a = QuickLayoutGrid.Cell(column: 3, row: 2)
        let b = QuickLayoutGrid.Cell(column: 1, row: 0)
        let rect = QuickLayoutGrid.unitRect(from: a, to: b, columns: 4, rows: 4)
        XCTAssertTrue(rect.isApproximatelyEqual(to: UnitRect(x: 0.25, y: 0, width: 0.75, height: 0.75)))
    }
}

final class PanelMetricsTests: XCTestCase {
    func testLargeWrapsIntoRows() {
        let metrics = PanelMetrics.make(style: .large, count: 7, aspect: 1.6)
        XCTAssertEqual(metrics.rows, 2)
        XCTAssertEqual(metrics.columns, 5)
        XCTAssertEqual(metrics.thumbnailFrame(at: 5).minY, metrics.thumbnailFrame(at: 0).minY
                       + metrics.cellSize.height + metrics.spacing)
    }

    func testHitTestFindsThumbnail() {
        let metrics = PanelMetrics.make(style: .compact, count: 3, aspect: 1.6)
        let frame = metrics.thumbnailFrame(at: 2)
        XCTAssertEqual(metrics.thumbnailIndex(at: CGPoint(x: frame.midX, y: frame.midY)), 2)
        XCTAssertNil(metrics.thumbnailIndex(at: CGPoint(x: 1, y: 1)))
    }

    func testListStacksVertically() {
        let metrics = PanelMetrics.make(style: .list, count: 4, aspect: 1.6)
        XCTAssertEqual(metrics.columns, 1)
        XCTAssertEqual(metrics.rows, 4)
        XCTAssertNotNil(metrics.labelFrame(at: 0))
    }
}

final class ConfigurationTests: XCTestCase {
    func testRoundTrip() throws {
        var config = Configuration()
        config.gap = 12
        config.panelStyle = .list
        config.workspaces = [Workspace(name: "Code", layoutID: config.layouts[0].id)]
        config.workspaces[0].assign(zoneID: config.layouts[0].zones[0].id, bundleID: "com.apple.Terminal",
                                    appName: "Terminal")
        let decoded = try ConfigStore.decode(ConfigStore.encode(config))
        XCTAssertEqual(decoded, config)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let decoded = try ConfigStore.decode(Data(#"{"gap": 8}"#.utf8))
        XCTAssertEqual(decoded.gap, 8)
        XCTAssertEqual(decoded.panelTrigger, .always)
        XCTAssertFalse(decoded.layouts.isEmpty)
        XCTAssertFalse(decoded.bindings.isEmpty)
    }

    func testSetComboMovesConflictingShortcut() {
        var config = Configuration(bindings: [])
        let combo = KeyCombo(keyCode: KeyCodes.leftArrow, modifiers: [.control, .option])
        config.setCombo(combo, for: .preset(.leftHalf))
        config.setCombo(combo, for: .preset(.leftThird))
        XCTAssertNil(config.combo(for: .preset(.leftHalf)))
        XCTAssertEqual(config.combo(for: .preset(.leftThird)), combo)
        config.setCombo(nil, for: .preset(.leftThird))
        XCTAssertTrue(config.bindings.isEmpty)
    }

    func testRemoveLayoutDropsReferences() {
        var config = Configuration()
        let layout = config.layouts[0]
        config.setCombo(KeyCombo(keyCode: KeyCodes.a, modifiers: [.command]),
                        for: .zone(layoutID: layout.id, zoneID: layout.zones[0].id))
        config.defaultLayoutID = layout.id
        config.displayLayouts["Built-in"] = layout.id
        config.removeLayout(id: layout.id)
        XCTAssertNil(config.layout(withID: layout.id))
        XCTAssertNil(config.defaultLayoutID)
        XCTAssertTrue(config.displayLayouts.isEmpty)
        XCTAssertFalse(config.bindings.contains { if case .zone = $0.action { return true }; return false })
    }

    func testPruneRemovesDanglingZoneReferences() {
        var config = Configuration()
        let layoutID = config.layouts[0].id
        let zoneID = config.layouts[0].zones[0].id
        config.workspaces = [Workspace(name: "W", layoutID: layoutID)]
        config.workspaces[0].assign(zoneID: zoneID, bundleID: "com.example", appName: "Example")
        config.setCombo(KeyCombo(keyCode: KeyCodes.b, modifiers: [.command]),
                        for: .zone(layoutID: layoutID, zoneID: zoneID))
        config.layouts[0].zones.removeFirst()
        config.pruneDanglingReferences()
        XCTAssertTrue(config.workspaces[0].assignments.isEmpty)
        XCTAssertNil(config.combo(for: .zone(layoutID: layoutID, zoneID: zoneID)))
    }

    func testOverlayLayoutResolution() {
        var config = Configuration()
        let second = config.layouts[1]
        let third = config.layouts[2]
        XCTAssertEqual(config.overlayLayout(forDisplay: "X")?.id, config.layouts[0].id)
        config.defaultLayoutID = second.id
        XCTAssertEqual(config.overlayLayout(forDisplay: "X")?.id, second.id)
        config.displayLayouts["X"] = third.id
        XCTAssertEqual(config.overlayLayout(forDisplay: "X")?.id, third.id)
    }

    func testStoreSurvivesCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data("not json".utf8).write(to: url)

        let store = ConfigStore(url: url)
        let loaded = store.load()
        XCTAssertEqual(loaded.layouts.count, TileLayout.defaultLayouts().count)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(backups.contains { $0.hasPrefix("config.corrupt-") })

        try store.save(loaded)
        XCTAssertEqual(store.load(), loaded)
    }

    func testDefaultBindingsAreUnique() {
        let combos = HotKeyBinding.defaults().map(\.combo)
        XCTAssertEqual(Set(combos).count, combos.count)
    }

    func testKeyComboDisplay() {
        let combo = KeyCombo(keyCode: KeyCodes.leftArrow, modifiers: [.command, .control, .option, .shift])
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘←")
    }
}

final class MissionControlMatchingTests: XCTestCase {
    func testTitleScores() {
        XCTAssertEqual(ThumbnailMatcher.titleScore(thumbnail: "README.md", window: "README.md"), 4)
        XCTAssertEqual(ThumbnailMatcher.titleScore(thumbnail: "A very long…document.pdf",
                                                   window: "A very long title for a document.pdf"), 3)
        XCTAssertEqual(ThumbnailMatcher.titleScore(thumbnail: "A very long ti…",
                                                   window: "A very long title"), 3)
        XCTAssertEqual(ThumbnailMatcher.titleScore(thumbnail: "Inbox", window: "Inbox — 3 unread"), 2)
        XCTAssertEqual(ThumbnailMatcher.titleScore(thumbnail: "Notes", window: "", appName: "Notes"), 1)
        XCTAssertEqual(ThumbnailMatcher.titleScore(thumbnail: "Inbox", window: "Calendar"), 0)
        XCTAssertEqual(ThumbnailMatcher.titleScore(thumbnail: "Untitled", window: ""), 0)
    }

    func testBestMatchPrefersTitleThenShape() {
        let candidates = [
            ThumbnailMatcher.Candidate(title: "Terminal", appName: "Terminal", bundleID: "com.apple.Terminal", aspect: 1.6),
            ThumbnailMatcher.Candidate(title: "Terminal", appName: "Terminal", bundleID: "com.apple.Terminal", aspect: 0.8),
            ThumbnailMatcher.Candidate(title: "Docs", appName: "Safari", bundleID: "com.apple.Safari", aspect: 0.8),
        ]
        XCTAssertEqual(ThumbnailMatcher.bestMatch(thumbnailTitle: "Terminal", thumbnailAspect: 0.75,
                                                  candidates: candidates), 1)
        XCTAssertEqual(ThumbnailMatcher.bestMatch(thumbnailTitle: "Terminal", thumbnailAspect: 1.5,
                                                  candidates: candidates), 0)
        XCTAssertEqual(ThumbnailMatcher.bestMatch(thumbnailTitle: "Docs", thumbnailAspect: 1,
                                                  candidates: candidates), 2)
        XCTAssertNil(ThumbnailMatcher.bestMatch(thumbnailTitle: "Docs", thumbnailAspect: 1,
                                                bundleID: "com.apple.Terminal", candidates: candidates))
        XCTAssertNil(ThumbnailMatcher.bestMatch(thumbnailTitle: "Mail", thumbnailAspect: 1, candidates: candidates))
    }

    func testBundleIDFromIdentifier() {
        XCTAssertEqual(MissionControlIdentifier.bundleID(from: "com.apple.Safari.space.3"), "com.apple.Safari")
        XCTAssertEqual(MissionControlIdentifier.bundleID(from: "com.example.space.app.space.12"), "com.example.space.app")
        XCTAssertNil(MissionControlIdentifier.bundleID(from: "mc.display"))
        XCTAssertNil(MissionControlIdentifier.bundleID(from: nil))
    }

    func testReadingOrder() {
        let frames = [
            CGRect(x: 600, y: 420, width: 300, height: 200), // row 2, right
            CGRect(x: 50, y: 100, width: 300, height: 200),  // row 1, left
            CGRect(x: 100, y: 430, width: 300, height: 180), // row 2, left
            CGRect(x: 500, y: 90, width: 300, height: 220),  // row 1, right
        ]
        XCTAssertEqual(ReadingOrder.sorted(frames), [1, 3, 2, 0])
        XCTAssertEqual(ReadingOrder.sorted([]), [])
    }

    func testMissionControlSettingsDefaultOnAndDecodeLeniently() throws {
        XCTAssertTrue(Configuration().missionControlEnabled)
        let decoded = try ConfigStore.decode(Data(#"{"missionControlTiling": false}"#.utf8))
        XCTAssertTrue(decoded.missionControlEnabled)
        XCTAssertFalse(decoded.missionControlTiling)
    }

    func testMetricsOverrides() {
        let metrics = PanelMetrics.make(style: .compact, count: 6, aspect: 2, thumbnailWidth: 80, perRow: 3)
        XCTAssertEqual(metrics.thumbnailSize, CGSize(width: 80, height: 40))
        XCTAssertEqual(metrics.rows, 2)
        XCTAssertEqual(metrics.columns, 3)
    }
}
