// GlobalShortcut.swift
// Feste Tastenkürzel wie ⌃⌥W und die Fenster-Kürzel. Jedes wird einzeln bei Apples Funktion für
// globale Tastenkürzel angemeldet (RegisterEventHotKey): macOS meldet Wad nur genau diese
// Kombinationen, Wad sieht keine anderen Tastenanschläge (SPEC 2.1).

import AppKit
import Carbon.HIToolbox

/// Eine Tastenkombination: eine Taste plus Sondertasten, so wie macOS sie anmeldet.
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    /// Carbon-Kennzeichen: cmdKey, shiftKey, optionKey, controlKey.
    var modifiers: UInt32

    static func command(shift: Bool = false, _ key: Int) -> KeyCombo {
        KeyCombo(keyCode: UInt32(key), modifiers: UInt32(cmdKey | (shift ? shiftKey : 0)))
    }

    /// Lesbar wie in Apples Menüs, zum Beispiel „⌘⇧F“.
    var displayName: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    private static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Return: "↩", kVK_Space: "Leertaste", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        ]
        if let name = special[Int(code)] { return name }
        // Den Buchstaben so zeigen, wie er auf der aktuellen Tastatur steht (deutsch: Z und Y richtig).
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event?.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Meldet Kürzel an und ab und ruft beim Drücken die passende Aktion auf.
final class HotKeyCenter {
    private var registered: [UInt32: (ref: EventHotKeyRef, action: () -> Void)] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue().registered[id.id]?.action()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        registered.values.forEach { UnregisterEventHotKey($0.ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Meldet ein Kürzel an. Rückgabe `nil`, wenn macOS es nicht hergibt, etwa weil es schon belegt ist.
    @discardableResult
    func register(_ combo: KeyCombo, action: @escaping () -> Void) -> UInt32? {
        var ref: EventHotKeyRef?
        let id = nextID
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: OSType(0x5741_4421), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        nextID += 1
        registered[id] = (ref, action)
        return id
    }

    func unregister(_ id: UInt32) {
        guard let entry = registered.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(entry.ref)
    }
}
