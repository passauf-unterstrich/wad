// WindowManager.swift
// Der Fenstermanager als abgeschotteter Baustein (SPEC 1.8): verwaltet die Fenster-Kürzel,
// meldet sie an, solange der Schalter an ist, und merkt sich eigene Belegungen.
// Mit Aufnahme und Einfügen hat er nichts zu tun.

import Carbon.HIToolbox
import Foundation

final class WindowManager {
    /// Standardbelegung nach Linus' Entscheidung vom 19.10.2026; Zentrieren ⌃⌥C.
    static let defaultShortcuts: [WindowAction: KeyCombo] = [
        .maximize: .command(shift: true, kVK_ANSI_F),
        .left: .command(shift: true, kVK_LeftArrow),
        .right: .command(shift: true, kVK_RightArrow),
        .top: .command(shift: true, kVK_UpArrow),
        .bottom: .command(shift: true, kVK_DownArrow),
        .topLeft: KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(optionKey | shiftKey)),
        .topRight: KeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: UInt32(optionKey | shiftKey)),
        .bottomRight: KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey | shiftKey)),
        .bottomLeft: KeyCombo(keyCode: UInt32(kVK_DownArrow), modifiers: UInt32(optionKey | shiftKey)),
        .center: KeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey)),
    ]

    /// Grundkürzel, ohne die man am Mac nicht arbeiten kann. Auch Wads eigenes Einfügen braucht ⌘V.
    static let reservedCombos: Set<KeyCombo> = Set(
        [kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_Q, kVK_ANSI_W, kVK_Tab]
            .map { KeyCombo.command($0) }
    )

    private static let enabledKey = "Fenstermanager"
    private static let shortcutsKey = "Fenster-Kürzel"

    /// Wird vor jeder Fenster-Aktion aufgerufen, etwa um eine versehentlich gestartete Aufnahme zu verwerfen.
    var willPerform: (() -> Void)?

    private(set) var shortcuts: [WindowAction: KeyCombo]
    private let hotKeys: HotKeyCenter
    private let mover = WindowMover()
    private var registeredIDs: [UInt32] = []

    /// Während im Fenster „Fenster-Kürzel“ eine neue Kombination aufgenommen wird, sind alle
    /// Fenster-Kürzel abgemeldet. Sonst würde ein schon belegtes Kürzel das Fenster verschieben,
    /// statt im Aufnahmefeld anzukommen.
    var isRecordingShortcut = false {
        didSet { registerAll() }
    }

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            registerAll()
        }
    }

    init(hotKeys: HotKeyCenter) {
        self.hotKeys = hotKeys
        // Standard: an (Linus' Entscheidung vom 19.10.2026). Wer ihn ausschaltet, dem merkt Wad das.
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        let saved = UserDefaults.standard.data(forKey: Self.shortcutsKey)
            .flatMap { try? JSONDecoder().decode([WindowAction: KeyCombo].self, from: $0) }
        shortcuts = saved ?? Self.defaultShortcuts
        registerAll()
    }

    /// Belegt eine Aktion neu. Rückgabe ist ein verständlicher Grund, falls es nicht geht.
    func setShortcut(_ combo: KeyCombo, for action: WindowAction) -> String? {
        if Self.reservedCombos.contains(combo) {
            return L10n.t("shortcuts.reserved", combo.displayName)
        }
        if let other = shortcuts.first(where: { $0.value == combo && $0.key != action })?.key {
            return L10n.t("shortcuts.taken", combo.displayName, other.title)
        }
        let previous = shortcuts[action]
        shortcuts[action] = combo
        registerAll()
        if isEnabled && !isRegistered(action) {
            shortcuts[action] = previous
            registerAll()
            return L10n.t("shortcuts.occupied", combo.displayName)
        }
        save()
        return nil
    }

    func resetToDefaults() {
        shortcuts = Self.defaultShortcuts
        save()
        registerAll()
    }

    private var registeredActions: Set<WindowAction> = []

    private func isRegistered(_ action: WindowAction) -> Bool {
        registeredActions.contains(action)
    }

    /// Meldet alles ab und, solange der Schalter an ist, neu an. Ist er aus, belegt Wad kein Kürzel.
    private func registerAll() {
        registeredIDs.forEach(hotKeys.unregister)
        registeredIDs.removeAll()
        registeredActions.removeAll()
        guard isEnabled, !isRecordingShortcut else { return }
        for (action, combo) in shortcuts {
            let id = hotKeys.register(combo) { [weak self] in
                self?.willPerform?()
                self?.mover.perform(action)
            }
            if let id {
                registeredIDs.append(id)
                registeredActions.insert(action)
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: Self.shortcutsKey)
        }
    }
}
