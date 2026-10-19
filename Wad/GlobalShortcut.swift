// GlobalShortcut.swift
// Das Tastenkürzel ⌃⌥W zum Korrigieren. Es nutzt Apples Funktion für globale Tastenkürzel
// (RegisterEventHotKey): macOS meldet Wad nur genau diese eine Kombination, keine anderen Tasten.

import Carbon.HIToolbox

final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// Ctrl+Option+W, „W“ wie Wad.
    init(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().action()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)

        let id = EventHotKeyID(signature: OSType(0x5741_4421), id: 1)   // „WAD!“
        RegisterEventHotKey(UInt32(kVK_ANSI_W), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
