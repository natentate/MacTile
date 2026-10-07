# MacTile

A native macOS menu bar app for drag-and-drop window snapping and custom layouts,
modelled on [Mosaic](https://lightpillar.com/mosaic.html) by Light Pillar.
Swift, AppKit + SwiftUI, no third-party dependencies. Requires macOS 13 Ventura or later.

> MacTile is an independent project and is not affiliated with Light Pillar.

## Features

| Feature | How it works in MacTile |
| --- | --- |
| **Drag & drop layouts** | Start dragging any window and a panel of layout thumbnails appears. Drop the window on a zone of any thumbnail to resize and place it there. |
| **Panel trigger** | Always while dragging, only while holding a modifier, only when dragged to the top of the screen, or never. |
| **Layout views** | Large thumbnails, compact thumbnails or a list; panel at the top of the screen, centred, or next to the pointer. |
| **Basic & advanced layouts** | Grid layouts (one zone per cell) or free-form layouts with any number of zones, including overlapping and nested zones. |
| **Layout editor** | Draw zones by dragging on a snapping grid; move, resize, split left/right or top/bottom, delete; per-layout grid resolution. |
| **Quick Layout** | Press a shortcut, drag across a grid, and the focused window takes that size. A one-off layout with no setup. |
| **Layout picker** | Keyboard-triggered version of the panel. Click a zone to apply it to the focused window. |
| **Zone overlay** | Hold ⇧ (configurable) while dragging to see the display's layout full screen, then drop into a zone. Layout can be set per display. |
| **Edge snapping** | Drag to the left or right edge for halves, a corner for quarters, the top for maximize. |
| **Keyboard shortcuts** | System-wide shortcuts for halves, quarters, thirds, two-thirds, maximize, center, restore, next/previous display, every zone of every layout, and every workspace. |
| **Workspaces** | Assign apps to the zones of a layout and arrange them all with one shortcut. Can launch apps that aren't running. |
| **Restore** | Dragging a snapped window out of its zone gives back its original size. A shortcut restores the pre-snap frame. |
| **Gaps** | Optional, even spacing between windows and around screen edges. |
| **Multi-display** | Works on every display. Move windows between displays with their relative size kept. |
| **Exclusions** | Apps MacTile should never touch. |
| **Portable config** | Settings live in one JSON file. Export, import and reset are in Settings. |

## Build and run

You need Xcode 15 or later (or its command line tools).

```bash
make app        # builds build/MacTile.app (universal, ad-hoc signed)
make run        # builds and opens it
make install    # copies it to /Applications and opens it
make test       # runs the unit tests
```

`swift run MacTile` also works for quick iteration. Launch at login only works from the
bundled `.app`.

### Accessibility permission

MacTile moves other apps' windows through the macOS Accessibility API. On first launch,
macOS asks you to allow it under **System Settings → Privacy & Security → Accessibility**.
The menu bar icon shows a warning until access is granted.

Each rebuild with an ad-hoc signature looks like a new app to macOS. After rebuilding,
remove MacTile from the Accessibility list and add it again. Signing with a stable
identity (`SIGN_IDENTITY="Developer ID Application: …" make app`) avoids this.

## Default shortcuts

| Action | Shortcut |
| --- | --- |
| Left / Right / Top / Bottom half | ⌃⌥← / ⌃⌥→ / ⌃⌥↑ / ⌃⌥↓ |
| Top left / Top right / Bottom left / Bottom right | ⌃⌥U / ⌃⌥I / ⌃⌥J / ⌃⌥K |
| Left / Center / Right third | ⌃⌥D / ⌃⌥F / ⌃⌥G |
| Left / Right two thirds | ⌃⌥E / ⌃⌥T |
| Maximize | ⌃⌥↩ |
| Center | ⌃⌥C |
| Restore | ⌃⌥⌫ |
| Next / Previous display | ⌃⌥⌘→ / ⌃⌥⌘← |
| Quick Layout | ⌃⌥Space |
| Layout picker | ⌃⌥L |

Change any of them, or bind layout zones and workspaces, under **Settings → Shortcuts**.

## Configuration file

`~/Library/Application Support/MacTile/config.json`. Changes in Settings are saved
automatically. Hand edits are picked up on the next launch. Any missing keys fall back to
their defaults. If the file can't be read, it is moved aside as `config.corrupt-<timestamp>.json`
rather than overwritten.

Zones are stored as fractions of a display's usable area, with the origin at the top left,
so a layout looks the same on any display:

```json
{
  "name": "Main + Stack",
  "columns": 2,
  "rows": 2,
  "showInPanel": true,
  "zones": [
    { "id": "…", "rect": { "x": 0,   "y": 0,   "width": 0.5, "height": 1   } },
    { "id": "…", "rect": { "x": 0.5, "y": 0,   "width": 0.5, "height": 0.5 } },
    { "id": "…", "rect": { "x": 0.5, "y": 0.5, "width": 0.5, "height": 0.5 } }
  ]
}
```

## Architecture

```
Sources/
├── MacTileCore/            Pure Swift, no AppKit. Fully unit tested.
│   ├── UnitRect.swift      Resolution-independent rects, grid snapping
│   ├── Layout.swift        Zones, layouts, hit testing, split, default layouts
│   ├── WindowAction.swift  Snap presets and every bindable action
│   ├── KeyCombo.swift      Shortcuts, key names, default bindings
│   ├── Workspace.swift     App-to-zone arrangements
│   ├── Geometry.swift      Unit rect → frame with gaps, edge snapping, Quick Layout grid
│   ├── PanelMetrics.swift  Thumbnail layout for the drag panel
│   ├── Configuration.swift All settings, lenient decoding, reference cleanup
│   └── ConfigStore.swift   JSON persistence
└── MacTile/                The app
    ├── main.swift / AppController.swift   Lifecycle and action routing
    ├── Accessibility/AXWindow.swift       Read and set window frames via AXUIElement
    ├── Drag/DragSnapController.swift      Global mouse monitor → drag detection → drop targets
    ├── Panels/                            Layout panel, zone overlay, snap preview, Quick Layout
    ├── HotKeys/HotKeyController.swift     Carbon RegisterEventHotKey (no extra permission)
    ├── Menu/StatusMenuController.swift    Menu bar menu
    ├── Preferences/                       SwiftUI settings (General, Layouts, Shortcuts, Workspaces, Exclusions)
    └── Support/                           App state, window manager, screen geometry, workspace launcher
```

**How drag detection works.** A global `NSEvent` monitor watches left mouse down, drag
and up. On mouse down MacTile finds the window under the pointer with
`AXUIElementCopyElementAtPosition`. When the pointer moves, it checks whether that
window's position changed while its size stayed the same. That pattern means the window is
being moved, whether by its title bar, a toolbar or a tab strip, and not resized and not
receiving a click. From then on, every mouse event re-evaluates the drop targets in
priority order: zone overlay, then layout panel, then edge snapping. A translucent
preview shows where the window will land. On mouse up the window is moved through the
Accessibility API.

All overlays are borderless, non-activating `NSPanel`s that ignore the mouse. The app you
are dragging keeps focus and keeps receiving the drag.

## Not included

Mosaic's Touch Bar support and iOS remote control app are out of scope.
Its constraint-based "advanced layouts" are covered by free-form zones on a grid of up
to 24 × 24.
