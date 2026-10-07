import Foundation

/// A keyboard shortcut: a virtual key code (`kVK_*`) plus modifiers.
public struct KeyCombo: Codable, Hashable {
    public struct Modifiers: OptionSet, Codable, Hashable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)

        /// Symbols in the order macOS displays them.
        public var symbols: String {
            var s = ""
            if contains(.control) { s += "⌃" }
            if contains(.option) { s += "⌥" }
            if contains(.shift) { s += "⇧" }
            if contains(.command) { s += "⌘" }
            return s
        }
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String {
        modifiers.symbols + KeyCodes.name(for: keyCode)
    }
}

/// Virtual key codes from `Carbon.HIToolbox.Events` (`kVK_*`), duplicated here so the
/// core module stays free of Carbon.
public enum KeyCodes {
    public static let a: UInt32 = 0x00, s: UInt32 = 0x01, d: UInt32 = 0x02, f: UInt32 = 0x03
    public static let h: UInt32 = 0x04, g: UInt32 = 0x05, z: UInt32 = 0x06, x: UInt32 = 0x07
    public static let c: UInt32 = 0x08, v: UInt32 = 0x09, b: UInt32 = 0x0B, q: UInt32 = 0x0C
    public static let w: UInt32 = 0x0D, e: UInt32 = 0x0E, r: UInt32 = 0x0F, y: UInt32 = 0x10
    public static let t: UInt32 = 0x11, o: UInt32 = 0x1F, u: UInt32 = 0x20, i: UInt32 = 0x22
    public static let p: UInt32 = 0x23, l: UInt32 = 0x25, j: UInt32 = 0x26, k: UInt32 = 0x28
    public static let n: UInt32 = 0x2D, m: UInt32 = 0x2E
    public static let returnKey: UInt32 = 0x24, tab: UInt32 = 0x30, space: UInt32 = 0x31
    public static let delete: UInt32 = 0x33, escape: UInt32 = 0x35, forwardDelete: UInt32 = 0x75
    public static let leftArrow: UInt32 = 0x7B, rightArrow: UInt32 = 0x7C
    public static let downArrow: UInt32 = 0x7D, upArrow: UInt32 = 0x7E

    private static let names: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=",
        0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U",
        0x21: "[", 0x22: "I", 0x23: "P", 0x24: "↩", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x30: "⇥",
        0x31: "Space", 0x32: "`", 0x33: "⌫", 0x35: "⎋", 0x41: "Keypad .", 0x43: "Keypad *",
        0x45: "Keypad +", 0x47: "Clear", 0x4B: "Keypad /", 0x4C: "⌤", 0x4E: "Keypad -",
        0x51: "Keypad =", 0x52: "Keypad 0", 0x53: "Keypad 1", 0x54: "Keypad 2", 0x55: "Keypad 3",
        0x56: "Keypad 4", 0x57: "Keypad 5", 0x58: "Keypad 6", 0x59: "Keypad 7", 0x5B: "Keypad 8",
        0x5C: "Keypad 9", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3", 0x64: "F8", 0x65: "F9",
        0x67: "F11", 0x69: "F13", 0x6A: "F16", 0x6B: "F14", 0x6D: "F10", 0x6F: "F12", 0x71: "F15",
        0x72: "Help", 0x73: "↖", 0x74: "⇞", 0x75: "⌦", 0x76: "F4", 0x77: "↘", 0x78: "F2",
        0x79: "⇟", 0x7A: "F1", 0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x40: "F17",
        0x4F: "F18", 0x50: "F19", 0x5A: "F20",
    ]

    /// Function keys may be used as shortcuts without a modifier.
    public static let functionKeys: Set<UInt32> = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F,
        0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
    ]

    public static func name(for keyCode: UInt32) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}

/// A shortcut bound to an action.
public struct HotKeyBinding: Codable, Hashable, Identifiable {
    public var id: UUID
    public var action: WindowAction
    public var combo: KeyCombo

    public init(id: UUID = UUID(), action: WindowAction, combo: KeyCombo) {
        self.id = id
        self.action = action
        self.combo = combo
    }

    public static func defaults() -> [HotKeyBinding] {
        let ctrlOpt: KeyCombo.Modifiers = [.control, .option]
        let ctrlOptCmd: KeyCombo.Modifiers = [.control, .option, .command]
        let table: [(WindowAction, UInt32, KeyCombo.Modifiers)] = [
            (.preset(.leftHalf), KeyCodes.leftArrow, ctrlOpt),
            (.preset(.rightHalf), KeyCodes.rightArrow, ctrlOpt),
            (.preset(.topHalf), KeyCodes.upArrow, ctrlOpt),
            (.preset(.bottomHalf), KeyCodes.downArrow, ctrlOpt),
            (.preset(.topLeft), KeyCodes.u, ctrlOpt),
            (.preset(.topRight), KeyCodes.i, ctrlOpt),
            (.preset(.bottomLeft), KeyCodes.j, ctrlOpt),
            (.preset(.bottomRight), KeyCodes.k, ctrlOpt),
            (.preset(.leftThird), KeyCodes.d, ctrlOpt),
            (.preset(.centerThird), KeyCodes.f, ctrlOpt),
            (.preset(.rightThird), KeyCodes.g, ctrlOpt),
            (.preset(.leftTwoThirds), KeyCodes.e, ctrlOpt),
            (.preset(.rightTwoThirds), KeyCodes.t, ctrlOpt),
            (.preset(.maximize), KeyCodes.returnKey, ctrlOpt),
            (.center, KeyCodes.c, ctrlOpt),
            (.restore, KeyCodes.delete, ctrlOpt),
            (.nextDisplay, KeyCodes.rightArrow, ctrlOptCmd),
            (.previousDisplay, KeyCodes.leftArrow, ctrlOptCmd),
            (.quickLayout, KeyCodes.space, ctrlOpt),
            (.layoutPicker, KeyCodes.l, ctrlOpt),
        ]
        return table.map { HotKeyBinding(action: $0.0, combo: KeyCombo(keyCode: $0.1, modifiers: $0.2)) }
    }
}
