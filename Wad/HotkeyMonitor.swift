// HotkeyMonitor.swift
// Beobachtet ausschließlich Sondertasten-Ereignisse (flagsChanged) und meldet nur,
// ob die rechte Option-Taste gedrückt oder losgelassen wurde. Normale Tastenanschläge
// werden nie abonniert, Wad sieht also nie, welche Buchstaben getippt werden (SPEC 2.1).

import AppKit

final class HotkeyMonitor {
    /// Wird mit `true` beim Drücken und `false` beim Loslassen der rechten Option-Taste aufgerufen.
    var onChange: ((Bool) -> Void)?

    private var monitors: [Any] = []

    /// Startet die Beobachtung. Mehrfaches Aufrufen ist harmlos, es läuft immer genau ein Paar Beobachter.
    func start() {
        stop()
        // Global: Ereignisse, während eine andere App vorne ist (braucht die Bedienungshilfen-Berechtigung).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        // Lokal: Ereignisse, während Wads eigenes Menü offen ist. Die erreichen den globalen Beobachter nicht.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }

        log.notice("Tasten-Beobachter gestartet: \(self.monitors.count, privacy: .public) von 2")
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        guard let isPressed = Self.rightOptionState(in: event) else { return }
        onChange?(isPressed)
    }

    /// Wertet ein flagsChanged-Ereignis aus.
    /// Rückgabe: `true` = rechte Option-Taste wurde gedrückt, `false` = losgelassen,
    /// `nil` = das Ereignis betrifft eine andere Sondertaste und wird verworfen.
    static func rightOptionState(in event: NSEvent) -> Bool? {
        guard event.keyCode == rightOptionKeyCode else { return nil }
        // Nicht `.option` abfragen: Das ist auch gesetzt, solange die linke Option-Taste gehalten wird.
        return event.modifierFlags.rawValue & rightOptionFlag != 0
    }

    /// Tastencode der rechten Option-Taste (Apple: kVK_RightOption).
    private static let rightOptionKeyCode: UInt16 = 61
    /// Bit in den Flags, das nur für die rechte Option-Taste steht (Apple: NX_DEVICERALTKEYMASK).
    private static let rightOptionFlag: UInt = 0x40
}
