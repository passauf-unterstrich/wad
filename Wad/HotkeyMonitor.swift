// HotkeyMonitor.swift
// Beobachtet ausschließlich Sondertasten-Ereignisse (flagsChanged) und meldet nur,
// ob die rechte Option-Taste gedrückt oder losgelassen wurde. Normale Tastenanschläge
// werden nie abonniert, Wad sieht also nie, welche Buchstaben getippt werden (SPEC 2.1).
// Für den Doppeltipp fragt Wad nur beim System nach, wie lange der letzte Tastenanschlag her ist,
// nie welcher es war.

import AppKit

final class HotkeyMonitor {
    /// Wird mit `true` beim Drücken und `false` beim Loslassen der rechten Option-Taste aufgerufen.
    /// `isAlone` heißt: Seit dem vorigen Drücken oder Loslassen dieser Taste kam keine andere Taste
    /// und keine andere Sondertaste dazu. Nur solche Tipps zählen für den Doppeltipp.
    var onChange: ((_ isPressed: Bool, _ isAlone: Bool) -> Void)?

    private var monitors: [Any] = []
    /// Zeitpunkte in Sekunden seit dem Systemstart, wie `NSEvent.timestamp`.
    private var lastRightOption: TimeInterval = 0
    private var lastOtherModifier: TimeInterval = 0

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
        // Ereignisse, die Wad selbst ausgelöst hat (das Cmd+V beim Einfügen), zählen nie als Tastendruck.
        guard event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) != Int64(getpid()) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let isPressed = Self.rightOptionState(in: event) else {
            lastOtherModifier = now
            return
        }
        let isAlone = !Self.holdsOtherModifiers(event.modifierFlags)
            && lastOtherModifier < lastRightOption
            && !Self.keyTyped(within: now - lastRightOption)
        lastRightOption = now
        onChange?(isPressed, isAlone)
    }

    /// Wird außer der rechten Option-Taste noch eine Sondertaste gehalten? Feststelltaste zählt nicht.
    private static func holdsOtherModifiers(_ flags: NSEvent.ModifierFlags) -> Bool {
        !flags.intersection([.shift, .control, .command, .function]).isEmpty
            || flags.rawValue & leftOptionFlag != 0
    }

    /// Kam in den letzten `seconds` Sekunden irgendein Tastenanschlag? Das System nennt nur die Zeit
    /// seit dem letzten Anschlag, nicht welche Taste es war.
    private static func keyTyped(within seconds: TimeInterval) -> Bool {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) <= seconds
    }

    /// Wertet ein flagsChanged-Ereignis aus.
    /// Rückgabe: `true` = rechte Option-Taste wurde gedrückt, `false` = losgelassen,
    /// `nil` = das Ereignis betrifft eine andere Sondertaste und wird verworfen.
    static func rightOptionState(in event: NSEvent) -> Bool? {
        guard event.keyCode == rightOptionKeyCode else { return nil }
        // Nicht `.option` abfragen: Das ist auch gesetzt, solange die linke Option-Taste gehalten wird.
        return event.modifierFlags.rawValue & rightOptionFlag != 0
    }

    /// Fragt direkt beim System nach, ob die rechte Option-Taste in diesem Moment unten ist,
    /// unabhängig von Ereignissen. Grundlage der Gegenprüfung während der Aufnahme (SPEC 2.2).
    static func isRightOptionDown() -> Bool {
        UInt(CGEventSource.flagsState(.hidSystemState).rawValue) & rightOptionFlag != 0
    }

    /// Tastencode der rechten Option-Taste (Apple: kVK_RightOption).
    private static let rightOptionKeyCode: UInt16 = 61
    /// Bit in den Flags, das nur für die rechte Option-Taste steht (Apple: NX_DEVICERALTKEYMASK).
    private static let rightOptionFlag: UInt = 0x40
    /// Dasselbe für die linke Option-Taste (Apple: NX_DEVICELALTKEYMASK).
    private static let leftOptionFlag: UInt = 0x20
}
