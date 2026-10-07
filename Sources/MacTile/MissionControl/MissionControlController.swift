import AppKit
import MacTileCore

/// Adds controls to Mission Control (and App Exposé):
///
/// - a close button on every window thumbnail;
/// - on hover, minimize / hide / layout buttons, the last opening a picker that snaps the
///   window into any zone of any layout;
/// - a "Tile" button per display that arranges that display's windows into a layout;
/// - ⌘W close, ⌘M minimize, ⌘H hide, ⌘Q quit for the thumbnail under the pointer.
///
/// Overlays are drawn in click-through panels above Mission Control. Clicks and keys are read
/// with an event tap that is only installed while Mission Control is open; it swallows events
/// that hit MacTile's controls and passes everything else to Mission Control untouched.
final class MissionControlController {
    enum Control: Equatable {
        case close(Int), minimize(Int), hide(Int), quit(Int), layouts(Int)
        case zone(Int, layoutID: UUID, zoneID: UUID)
        case popoverBackground(Int)
        case tileMenu(String)
        case tile(String, layoutID: UUID)
        case stripBackground(String)

        /// The thumbnail this control belongs to.
        var thumbnail: Int? {
            switch self {
            case .close(let i), .minimize(let i), .hide(let i), .quit(let i), .layouts(let i),
                 .zone(let i, _, _), .popoverBackground(let i):
                return i
            case .tileMenu, .tile, .stripBackground:
                return nil
            }
        }

        /// The display whose tile strip this control belongs to.
        var tileDisplay: String? {
            switch self {
            case .tileMenu(let key), .tile(let key, _), .stripBackground(let key): return key
            default: return nil
            }
        }

        var symbol: String? {
            switch self {
            case .close: return "xmark"
            case .minimize: return "minus"
            case .hide: return "eye.slash"
            case .layouts: return "rectangle.split.2x2"
            default: return nil
            }
        }
    }

    struct Region {
        let control: Control
        /// Top-left global coordinates.
        let rect: CGRect
    }

    private let state: AppState
    private let windows: WindowManager
    private var timer: Timer?

    private var active = false
    private var thumbnails: [MissionControlThumbnail] = []
    private var lastFrames: [CGRect] = []
    private var stablePolls = 0

    private var regions: [Region] = []
    private var strips: [MissionControlRenderModel.Strip] = []
    private var hoveredThumbnail: Int?
    private var hoveredControl: Control?
    private var pressedControl: Control?
    private var expandedThumbnail: Int?
    private var expandedTileDisplay: String?

    private var candidates: [(window: AXWindow, info: ThumbnailMatcher.Candidate)]?
    private var overlays: [String: (panel: OverlayPanel, view: MissionControlOverlayView)] = [:]
    private var eventTap: CFMachPort?
    private var tapSource: CFRunLoopSource?

    private let buttonSize: CGFloat = 24

    init(state: AppState, windows: WindowManager) {
        self.state = state
        self.windows = windows
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        deactivate()
    }

    // MARK: Detection

    private func poll() {
        let config = state.config
        guard config.isEnabled, config.missionControlEnabled, AccessibilityPermission.isTrusted,
              let scanned = MissionControlScanner.scan(), !scanned.isEmpty else {
            if active || !lastFrames.isEmpty { deactivate() }
            return
        }

        let frames = scanned.map(\.frame)
        let unchanged = frames.count == lastFrames.count
            && zip(frames, lastFrames).allSatisfy { $0.isClose(to: $1, tolerance: 1) }
        lastFrames = frames

        if unchanged {
            stablePolls += 1
        } else {
            // Opening, closing or re-laying out: hide controls until thumbnails settle.
            stablePolls = 0
            if active { clearControls() }
        }
        guard stablePolls == 2 else { return }

        thumbnails = scanned
        candidates = nil
        hoveredThumbnail = nil
        hoveredControl = nil
        expandedThumbnail = nil
        if !active {
            active = true
            installTap()
        }
        rebuild()
        updateHover(at: ScreenGeometry.flip(NSEvent.mouseLocation))
    }

    private func deactivate() {
        active = false
        thumbnails = []
        lastFrames = []
        stablePolls = 0
        candidates = nil
        hoveredThumbnail = nil
        hoveredControl = nil
        pressedControl = nil
        expandedThumbnail = nil
        expandedTileDisplay = nil
        regions = []
        strips = []
        removeTap()
        overlays.values.forEach { $0.panel.orderOut(nil) }
    }

    private func clearControls() {
        regions = []
        strips = []
        render()
    }

    // MARK: Layout of controls

    private func rebuild() {
        regions = []
        strips = []
        guard active else {
            render()
            return
        }
        let config = state.config
        let layouts = config.panelLayouts

        for (index, thumbnail) in thumbnails.enumerated() {
            let f = thumbnail.frame
            let s = buttonSize
            regions.append(Region(control: .close(index),
                                  rect: CGRect(x: f.minX - s / 2 + 4, y: f.minY - s / 2 + 4, width: s, height: s)))

            guard hoveredThumbnail == index || expandedThumbnail == index else { continue }
            var toolbar: [Control] = [.minimize(index), .hide(index)]
            if !layouts.isEmpty { toolbar.append(.layouts(index)) }
            for (offset, control) in toolbar.reversed().enumerated() {
                let x = f.maxX - CGFloat(offset + 1) * (s + 6) + s / 2 - 4
                regions.append(Region(control: control, rect: CGRect(x: x, y: f.minY - s / 2 + 4, width: s, height: s)))
            }

            if expandedThumbnail == index, !layouts.isEmpty, let screen = screen(for: f) {
                let area = ScreenGeometry.fullArea(of: screen)
                let metrics = PanelMetrics.make(style: .compact, count: layouts.count,
                                                aspect: area.width / max(area.height, 1),
                                                thumbnailWidth: 80, perRow: min(layouts.count, 4))
                let size = metrics.panelSize
                let proposed = CGRect(x: f.maxX - size.width, y: f.minY + s / 2 + 10,
                                      width: size.width, height: size.height)
                let background = LayoutGeometry.clamp(proposed, into: area.insetBy(dx: 8, dy: 8))
                addStrip(background: background, title: nil, layouts: layouts, metrics: metrics,
                         backgroundControl: .popoverBackground(index)) { layout, thumb in
                    for zone in layout.zones {
                        let rect = LayoutGeometry.rect(for: zone.rect, in: thumb.insetBy(dx: 3, dy: 3), inset: 1.5)
                        self.regions.append(Region(control: .zone(index, layoutID: layout.id, zoneID: zone.id),
                                                   rect: rect))
                    }
                }
            }
        }

        if config.missionControlTiling, !layouts.isEmpty {
            for screen in NSScreen.screens {
                let area = ScreenGeometry.fullArea(of: screen)
                guard thumbnails.contains(where: { area.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }) else {
                    continue
                }
                let key = screen.displayKey
                let usable = ScreenGeometry.usableArea(of: screen)
                let pill = CGRect(x: area.midX - 48, y: usable.maxY - 44, width: 96, height: 30)
                regions.append(Region(control: .tileMenu(key), rect: pill))

                guard expandedTileDisplay == key else { continue }
                let metrics = PanelMetrics.make(style: .compact, count: layouts.count,
                                                aspect: area.width / max(area.height, 1),
                                                thumbnailWidth: 76, perRow: min(layouts.count, 8))
                let header: CGFloat = 22
                let size = CGSize(width: metrics.panelSize.width, height: metrics.panelSize.height + header)
                let background = LayoutGeometry.clamp(
                    // Overlaps the pill slightly so moving the pointer up never crosses a gap.
                    CGRect(x: area.midX - size.width / 2, y: pill.minY - size.height + 4,
                           width: size.width, height: size.height),
                    into: area.insetBy(dx: 8, dy: 8))
                addStrip(background: background, title: "Tile this display's windows into…", layouts: layouts,
                         metrics: metrics, header: header, backgroundControl: .stripBackground(key)) { layout, thumb in
                    self.regions.append(Region(control: .tile(key, layoutID: layout.id), rect: thumb))
                }
            }
        }
        render()
    }

    /// Adds a panel of layout thumbnails. The background region is added first so the item
    /// regions (added by `items`) win hit-testing.
    private func addStrip(
        background: CGRect, title: String?, layouts: [TileLayout], metrics: PanelMetrics, header: CGFloat = 0,
        backgroundControl: Control, items: (TileLayout, CGRect) -> Void
    ) {
        regions.append(Region(control: backgroundControl, rect: background))
        var entries: [(layout: TileLayout, rect: CGRect)] = []
        for (i, layout) in layouts.enumerated() {
            let thumb = metrics.thumbnailFrame(at: i).offsetBy(dx: background.minX, dy: background.minY + header)
            entries.append((layout, thumb))
            items(layout, thumb)
        }
        let titleRect = title == nil ? nil
            : CGRect(x: background.minX + 12, y: background.minY + 8, width: background.width - 24, height: header)
        strips.append(MissionControlRenderModel.Strip(background: background, title: title, titleRect: titleRect,
                                                      items: entries))
    }

    private func render() {
        guard active else { return }
        let model = MissionControlRenderModel(regions: regions, strips: strips,
                                              hoveredControl: hoveredControl, pressedControl: pressedControl)
        var liveKeys = Set<String>()
        for screen in NSScreen.screens {
            let key = screen.displayKey
            liveKeys.insert(key)
            let overlay = overlays[key] ?? makeOverlay()
            overlays[key] = overlay
            if overlay.panel.frame != screen.frame || !overlay.panel.isVisible {
                overlay.panel.setFrame(screen.frame, display: false)
                overlay.view.frame = CGRect(origin: .zero, size: screen.frame.size)
                overlay.panel.orderFrontRegardless()
            }
            overlay.view.origin = ScreenGeometry.fullArea(of: screen).origin
            overlay.view.model = model
            overlay.view.needsDisplay = true
        }
        for (key, overlay) in overlays where !liveKeys.contains(key) {
            overlay.panel.orderOut(nil)
        }
    }

    private func makeOverlay() -> (panel: OverlayPanel, view: MissionControlOverlayView) {
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        let panel = OverlayPanel(level: level)
        // Stationary: Mission Control leaves the overlay in place instead of shuffling it.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = MissionControlOverlayView()
        panel.contentView = view
        return (panel, view)
    }

    // MARK: Input

    private func control(at point: CGPoint) -> Control? {
        regions.last { $0.rect.contains(point) }?.control
    }

    private func updateHover(at point: CGPoint) {
        guard active else { return }
        let control = self.control(at: point)
        var thumbnail = control?.thumbnail
            ?? thumbnails.indices.last { thumbnails[$0].frame.insetBy(dx: -12, dy: -12).contains(point) }
        var expanded = expandedThumbnail
        if let current = expanded, thumbnail != current {
            // Leaving the thumbnail and its picker closes the picker.
            expanded = nil
        }
        if expanded != nil { thumbnail = expanded }

        var tileDisplay = expandedTileDisplay
        if let key = control?.tileDisplay {
            tileDisplay = key
        } else if tileDisplay != nil {
            tileDisplay = nil
        }

        let layoutChanged = thumbnail != hoveredThumbnail || expanded != expandedThumbnail
            || tileDisplay != expandedTileDisplay
        hoveredThumbnail = thumbnail
        expandedThumbnail = expanded
        expandedTileDisplay = tileDisplay
        if layoutChanged {
            rebuild()
            hoveredControl = self.control(at: point)
            render()
        } else if control != hoveredControl {
            hoveredControl = control
            render()
        }
    }

    fileprivate func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return pass
        case .mouseMoved, .leftMouseDragged:
            updateHover(at: event.location)
            return pass
        case .leftMouseDown:
            guard active, let control = control(at: event.location) else { return pass }
            pressedControl = control
            render()
            return nil
        case .leftMouseUp:
            guard let pressed = pressedControl else { return pass }
            pressedControl = nil
            if control(at: event.location) == pressed {
                DispatchQueue.main.async { [weak self] in self?.perform(pressed) }
            }
            render()
            return nil
        case .keyDown:
            guard active, let index = hoveredThumbnail, event.flags.contains(.maskCommand) else { return pass }
            let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
            let control: Control
            switch keyCode {
            case KeyCodes.w: control = .close(index)
            case KeyCodes.m: control = .minimize(index)
            case KeyCodes.h: control = .hide(index)
            case KeyCodes.q: control = .quit(index)
            default: return pass
            }
            DispatchQueue.main.async { [weak self] in self?.perform(control) }
            return nil
        default:
            return pass
        }
    }

    private func installTap() {
        guard eventTap == nil else { return }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: missionControlTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        tapSource = source
    }

    private func removeTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        tapSource = nil
    }

    // MARK: Actions

    private func perform(_ control: Control) {
        guard active else { return }
        switch control {
        case .close(let index):
            guard let window = window(for: index) else { return }
            if !window.close() { NSSound.beep() }
            candidates = nil
        case .minimize(let index):
            window(for: index)?.minimize()
            candidates = nil
        case .hide(let index):
            window(for: index)?.runningApplication?.hide()
            candidates = nil
        case .quit(let index):
            window(for: index)?.runningApplication?.terminate()
            candidates = nil
        case .layouts(let index):
            expandedThumbnail = expandedThumbnail == index ? nil : index
            hoveredThumbnail = index
            rebuild()
        case .zone(let index, let layoutID, let zoneID):
            guard let zone = state.config.layout(withID: layoutID)?.zone(withID: zoneID),
                  let window = window(for: index), windows.canManage(window),
                  let screen = screen(for: thumbnails[index].frame) else {
                NSSound.beep()
                return
            }
            let windows = self.windows
            exitMissionControl {
                windows.apply(zone.rect, to: window, on: screen)
                MissionControlController.focus(window)
            }
        case .tileMenu(let key):
            expandedTileDisplay = expandedTileDisplay == key ? nil : key
            rebuild()
        case .tile(let key, let layoutID):
            tile(displayKey: key, layoutID: layoutID)
        case .popoverBackground, .stripBackground:
            break
        }
    }

    /// Places the display's windows into the layout's zones, in reading order of their thumbnails.
    private func tile(displayKey: String, layoutID: UUID) {
        guard let layout = state.config.layout(withID: layoutID),
              let screen = NSScreen.screens.first(where: { $0.displayKey == displayKey }) else { return }
        let area = ScreenGeometry.fullArea(of: screen)
        let onDisplay = thumbnails.indices.filter {
            area.contains(CGPoint(x: thumbnails[$0].frame.midX, y: thumbnails[$0].frame.midY))
        }
        let ordered = ReadingOrder.sorted(onDisplay.map { thumbnails[$0].frame }).map { onDisplay[$0] }

        var zones = layout.zones.makeIterator()
        var used = Set<WindowKey>()
        var plan: [(window: AXWindow, zone: Zone)] = []
        for index in ordered {
            guard let window = window(for: index), windows.canManage(window), !used.contains(window.key) else { continue }
            guard let zone = zones.next() else { break }
            used.insert(window.key)
            plan.append((window, zone))
        }
        guard !plan.isEmpty else {
            NSSound.beep()
            return
        }
        let windows = self.windows
        exitMissionControl {
            for step in plan.reversed() {
                windows.apply(step.zone.rect, to: step.window, on: screen)
                step.window.raise()
            }
            if let first = plan.first { MissionControlController.focus(first.window) }
        }
    }

    /// Leaves Mission Control (as Esc would), then runs `work` once its animation is done.
    private func exitMissionControl(then work: @escaping () -> Void) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCodes.escape), keyDown: keyDown)?
                .post(tap: .cghidEventTap)
        }
        deactivate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private static func focus(_ window: AXWindow) {
        window.raise()
        if let pid = window.pid {
            AXUIElementCreateApplication(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
        }
    }

    // MARK: Thumbnail → window

    private func screen(for thumbnailFrame: CGRect) -> NSScreen? {
        ScreenGeometry.screen(containing: ScreenGeometry.flip(CGPoint(x: thumbnailFrame.midX, y: thumbnailFrame.midY)))
    }

    private func window(for index: Int) -> AXWindow? {
        guard thumbnails.indices.contains(index) else { return nil }
        let thumbnail = thumbnails[index]
        let list = loadCandidates()
        let aspect = Double(thumbnail.frame.width / max(thumbnail.frame.height, 1))
        guard let match = ThumbnailMatcher.bestMatch(
            thumbnailTitle: thumbnail.title, thumbnailAspect: aspect,
            bundleID: thumbnail.bundleID, candidates: list.map(\.info)) else {
            NSSound.beep()
            return nil
        }
        return list[match].window
    }

    /// Every visible window of every regular app, read once per Mission Control session.
    private func loadCandidates() -> [(window: AXWindow, info: ThumbnailMatcher.Candidate)] {
        if let candidates { return candidates }
        var result: [(window: AXWindow, info: ThumbnailMatcher.Candidate)] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            element.setTimeout(0.3)
            for windowElement in element.elements(kAXWindowsAttribute) {
                let window = AXWindow(windowElement)
                guard window.role == kAXWindowRole, !window.isMinimized,
                      let frame = window.frame, frame.width > 0, frame.height > 0 else { continue }
                result.append((window, ThumbnailMatcher.Candidate(
                    title: window.title ?? "", appName: app.localizedName ?? "",
                    bundleID: app.bundleIdentifier, aspect: Double(frame.width / frame.height))))
            }
        }
        candidates = result
        return result
    }
}

private func missionControlTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<MissionControlController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handleTap(type: type, event: event)
}
