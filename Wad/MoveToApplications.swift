// MoveToApplications.swift
// Wer Wad direkt aus der geöffneten DMG startet, statt es in den Programme-Ordner zu ziehen,
// bekommt eine Rückfrage. Aus der DMG heraus würde Wad nach dem Auswerfen verschwinden, und
// der Start bei der Anmeldung ließe sich nicht einrichten.

import AppKit

enum MoveToApplications {
    /// Ganz am Anfang aufrufen, noch vor Berechtigungen und Menüleiste. Tut nichts, wenn Wad schon
    /// richtig liegt. Rückgabe `true` heißt: Die Kopie in Programme ist gestartet, diese Instanz endet.
    static func offerIfNeeded() -> Bool {
        let current = Bundle.main.bundleURL
        guard current.path.hasPrefix("/Volumes/") else { return false }
        NSApplication.shared.setActivationPolicy(.accessory)

        let alert = NSAlert()
        alert.messageText = "Wad in den Programme-Ordner bewegen?"
        alert.informativeText = "Wad läuft gerade direkt aus der heruntergeladenen Datei. Im Programme-Ordner startet Wad auch nach dem Auswerfen und auf Wunsch bei jeder Anmeldung."
        alert.addButton(withTitle: "Bewegen")
        alert.addButton(withTitle: "Nicht jetzt")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let target = URL(fileURLWithPath: "/Applications/Wad.app")
        do {
            // Eine ältere Wad-Version wird beendet und kommt in den Papierkorb, nicht endgültig weg.
            NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0 != .current }
                .forEach { $0.terminate() }
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.trashItem(at: target, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: current, to: target)
        } catch {
            log.error("Bewegen in Programme: \(error.localizedDescription, privacy: .public)")
            let failed = NSAlert()
            failed.messageText = "Das hat nicht geklappt"
            failed.informativeText = "Bitte ziehe Wad im Fenster der heruntergeladenen Datei selbst auf den Ordner „Programme“."
            failed.runModal()
            return false
        }

        // Die Kopie im Programme-Ordner übernimmt, diese Instanz aus der DMG beendet sich.
        return NSWorkspace.shared.open(target)
    }
}
