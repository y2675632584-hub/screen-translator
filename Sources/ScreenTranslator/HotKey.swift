import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let f8 = Shortcut(keyCode: UInt32(kVK_F8), modifiers: 0, keyLabel: "F8")

    var label: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined() + keyLabel
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown, !event.isARepeat else { return nil }
        let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierKeys.contains(event.keyCode) else { return nil }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        // Fn is also attached to F-keys and arrows by AppKit; it is not a Carbon modifier.
        let special: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "空格", 51: "Delete", 53: "Esc",
            76: "数字键盘 Enter", 114: "Help", 115: "Home", 116: "Page Up", 117: "⌦",
            119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13",
            107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
            65: "数字键盘 .", 67: "数字键盘 *", 69: "数字键盘 +", 71: "Clear",
            75: "数字键盘 /", 78: "数字键盘 −", 81: "数字键盘 =", 82: "数字键盘 0",
            83: "数字键盘 1", 84: "数字键盘 2", 85: "数字键盘 3", 86: "数字键盘 4",
            87: "数字键盘 5", 88: "数字键盘 6", 89: "数字键盘 7", 91: "数字键盘 8", 92: "数字键盘 9"
        ]
        let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
        let printable = characters.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let keyLabel = special[event.keyCode] ?? (printable.isEmpty ? "按键 \(event.keyCode)" : String(String.UnicodeScalarView(printable)).uppercased())
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: keyLabel)
    }

    static func load(from defaults: UserDefaults) -> Shortcut {
        if let data = defaults.data(forKey: "customShortcut"),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) { return saved }
        switch defaults.string(forKey: "shortcut") {
        case "optionSpace": return .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), keyLabel: "空格")
        case "commandShiftT": return .init(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "T")
        default: return .f8
        }
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "customShortcut") }
    }
}

/// Only listens while the settings window is recording; never reads typing in other apps.
@MainActor
final class ShortcutRecorder {
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var pending: Shortcut?
    var onCommit: ((Shortcut) -> Void)?
    var onCancel: (() -> Void)?
    var onHint: ((String) -> Void)?

    func begin() {
        end()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown:
                if self.pending == nil, let shortcut = Shortcut(event: event) {
                    self.pending = shortcut
                    self.onHint?("松开 \(shortcut.label) 即可保存")
                }
            case .keyUp:
                if let shortcut = self.pending, UInt32(event.keyCode) == shortcut.keyCode {
                    self.end()
                    self.onCommit?(shortcut)
                }
            case .flagsChanged:
                if self.pending == nil { self.onHint?("可同时按住修饰键，再按一个字母、数字或功能键") }
            default: break
            }
            return nil
        }
        for name in [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.end()
                    self?.onCancel?()
                }
            })
        }
    }

    func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        pending = nil
    }
}

final class HotKeyManager {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    private var held = false

    init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) { manager.held = false }
            else if !manager.held { manager.held = true; manager.onPress?() }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let identifier = EventHotKeyID(signature: 0x5354524E, id: 1)
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                  GetApplicationEventTarget(), 0, &reference) == noErr
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        held = false
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
