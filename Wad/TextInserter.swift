// TextInserter.swift
// Fügt Text an der Cursorposition ein, egal in welcher App: über die Zwischenablage und ein
// simuliertes Cmd+V. Danach stellt Wad den vorherigen Inhalt der Zwischenablage vollständig
// wieder her, sodass es aussieht, als hätte Wad sie nie benutzt (SPEC 2.5).

import AppKit

final class TextInserter {
    /// So lange bekommt die Ziel-App Zeit, die Zwischenablage zu lesen, bevor Wad sie zurücksetzt.
    /// Großzügig gewählt: Auch schwere Apps unter Last fügen so nie den alten Inhalt ein.
    static let restoreDelay: TimeInterval = 1.5

    /// Meldet, dass Wad den alten Inhalt zurückgelegt hat. Der Zwischenablage-Verlauf übergeht
    /// diese Änderung, sonst tauchte ein gelöschter Eintrag nach jedem Diktat wieder auf.
    var onRestored: (() -> Void)?

    /// Kennzeichnung nach nspasteboard.org: Zwischenablage-Programme (und Wads eigener Verlauf)
    /// übergehen so markierte Einträge, der Diktat-Text taucht dort also nie auf.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard
    private let restoreDelay: TimeInterval
    private let sendPasteShortcut: () -> Void
    /// Der gesicherte Inhalt und die geplante Wiederherstellung, solange sie noch aussteht.
    private var pending: (saved: [NSPasteboardItem], restore: DispatchWorkItem)?

    init(pasteboard: NSPasteboard = .general,
         restoreDelay: TimeInterval = TextInserter.restoreDelay,
         sendPasteShortcut: @escaping () -> Void = TextInserter.postCommandV) {
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
        self.sendPasteShortcut = sendPasteShortcut
    }

    func insert(_ text: String) {
        // Folgen zwei Stücke kurz aufeinander, liegt noch Wads eigener Text in der Zwischenablage.
        // Dann bleibt die ursprüngliche Sicherung gültig, statt den Diktat-Text zu sichern.
        let saved = pending?.saved ?? Self.snapshot(of: pasteboard)
        pending?.restore.cancel()

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let ownChange = pasteboard.changeCount

        sendPasteShortcut()

        let restore = DispatchWorkItem { [self] in
            pending = nil
            // Hat der Nutzer inzwischen selbst etwas kopiert, gehört die Zwischenablage ihm.
            guard pasteboard.changeCount == ownChange else { return }
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
            onRestored?()
        }
        pending = (saved, restore)
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay, execute: restore)
    }

    /// Kopiert jeden Eintrag in jedem Format, also auch Bilder, Dateien und formatierten Text.
    static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
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
    /// Eine eigene, private Ereignisquelle sorgt dafür, dass das System danach nicht glaubt, die
    /// Option-Taste sei losgelassen worden. Sonst beendete das Einfügen eines Live-Stücks die Aufnahme.
    static func postCommandV() {
        postCommand(key: 9)   // Taste V (Apple: kVK_ANSI_V), auf deutscher Tastatur an derselben Stelle
    }

    /// Drückt Cmd plus eine Taste, mit denselben Vorkehrungen wie Cmd+V.
    static func postCommand(key: CGKeyCode) {
        let source = CGEventSource(stateID: .privateState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }
    }
}
