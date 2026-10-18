// TextInserter.swift
// Fügt Text an der Cursorposition ein, egal in welcher App: über die Zwischenablage und ein
// simuliertes Cmd+V. Danach stellt Wad den vorherigen Inhalt der Zwischenablage vollständig
// wieder her, sodass es aussieht, als hätte Wad sie nie benutzt (SPEC 2.5).

import AppKit

final class TextInserter {
    /// So lange bekommt die Ziel-App Zeit, die Zwischenablage zu lesen, bevor Wad sie zurücksetzt.
    static let restoreDelay: TimeInterval = 0.5

    /// Kennzeichnung nach nspasteboard.org: Zwischenablage-Programme (und Wads eigener Verlauf)
    /// übergehen so markierte Einträge, der Diktat-Text taucht dort also nie auf.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard
    private let restoreDelay: TimeInterval
    private let sendPasteShortcut: () -> Void

    init(pasteboard: NSPasteboard = .general,
         restoreDelay: TimeInterval = TextInserter.restoreDelay,
         sendPasteShortcut: @escaping () -> Void = TextInserter.postCommandV) {
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
        self.sendPasteShortcut = sendPasteShortcut
    }

    func insert(_ text: String) {
        let saved = snapshot()

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let ownChange = pasteboard.changeCount

        sendPasteShortcut()

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) { [self] in
            // Hat der Nutzer inzwischen selbst etwas kopiert, gehört die Zwischenablage ihm.
            guard pasteboard.changeCount == ownChange else { return }
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
    }

    /// Kopiert jeden Eintrag in jedem Format, also auch Bilder, Dateien und formatierten Text.
    private func snapshot() -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    /// Drückt Cmd+V im Namen des Nutzers. Die Ereignisse tragen ausdrücklich nur Cmd, damit eine
    /// gerade gehaltene Option-Taste daraus kein anderes Tastenkürzel macht.
    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9   // Taste V (Apple: kVK_ANSI_V), auf deutscher Tastatur an derselben Stelle
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
