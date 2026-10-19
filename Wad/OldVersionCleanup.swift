// OldVersionCleanup.swift
// Räumt einmalig Linus' alte Diktier-App „Wispr“ (diktieren.py) auf, falls sie auf diesem Mac liegt.
// Sie belegt dieselbe rechte Option-Taste und käme Wad in die Quere.
//
// Gesucht wird nur an drei genau bekannten Stellen, gelesen wird sonst nichts. Wer die alte App nie
// hatte, merkt davon nichts: Wad prüft einmal, findet nichts und fragt nie wieder.
// Nichts wird endgültig gelöscht: Der alte Ordner kommt in den Papierkorb.

import AppKit

enum OldVersionCleanup {
    private static let doneKey = "Alte Version geprüft"
    private static let bundleID = "de.passaufunterstrich.wispr"
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    /// Dorthin hat das alte Installationsskript Wispr geklont. Nur diesen Ordner legt Wad in den Papierkorb.
    private static let installFolder = home.appendingPathComponent("Desktop/linus_apps/Wispr")
    /// Terminal-Befehle, die das alte Setup angelegt hat.
    private static let commandLinks = ["diktieren", "diktiere", "Diktieren", "Diktiere", "diktieren-update"]
        .map { home.appendingPathComponent(".local/bin/\($0)") }

    /// Einmal beim Start aufrufen.
    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let hasFolder = FileManager.default.fileExists(atPath: installFolder.path)
        let pythonPIDs = runningOldScripts()
        guard app != nil || hasFolder || !pythonPIDs.isEmpty else {
            UserDefaults.standard.set(true, forKey: doneKey)
            return
        }
        guard askUser() else { return }   // „Später“: beim nächsten Start wieder fragen

        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        pythonPIDs.forEach { kill($0, SIGTERM) }
        if let app { disableLoginItem(of: app) }
        if hasFolder { try? FileManager.default.trashItem(at: installFolder, resultingItemURL: nil) }
        removeCommandLinks()

        UserDefaults.standard.set(true, forKey: doneKey)
        log.notice("Alte Version aufgeräumt")
        let done = NSAlert()
        done.messageText = "Die alte Diktier-App ist aufgeräumt"
        done.informativeText = "Ab jetzt hört nur noch Wad auf die rechte Option-Taste. Die alten Dateien liegen im Papierkorb. Leere ihn, dann sind auch die alten Diktat-Verläufe endgültig gelöscht."
        done.runModal()
    }

    private static func askUser() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Alte Diktier-App gefunden"
        alert.informativeText = "Auf diesem Mac ist noch die frühere Diktier-App „Wispr“. Sie benutzt dieselbe Taste wie Wad. Soll Wad sie beenden, beim Anmelden nicht mehr starten lassen und ihre Dateien in den Papierkorb legen?"
        alert.addButton(withTitle: "Aufräumen")
        alert.addButton(withTitle: "Später")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Prozesse, die diktieren.py ausführen, also die Terminal-Variante. Nur die des eigenen Benutzers.
    private static func runningOldScripts() -> [pid_t] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-U", String(getuid()), "-f", "diktieren\\.py"]
        let output = Pipe()
        pgrep.standardOutput = output
        guard (try? pgrep.run()) != nil else { return [] }
        pgrep.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
    }

    /// Die alte App hat sich selbst als Anmeldeobjekt eingetragen. Austragen kann sie nur sie selbst,
    /// deshalb ruft Wad ihren eigenen Befehl dafür auf.
    private static func disableLoginItem(of app: URL) {
        let launcher = Process()
        launcher.executableURL = app.appendingPathComponent("Contents/MacOS/WisprLauncher")
        launcher.arguments = ["--login-item-disable"]
        guard (try? launcher.run()) != nil else { return }
        launcher.waitUntilExit()
    }

    /// Entfernt nur Verknüpfungen, die wirklich in den alten Ordner zeigen, nie fremde Dateien.
    private static func removeCommandLinks() {
        for link in commandLinks {
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path),
                  target.contains("linus_apps/Wispr") else { continue }
            try? FileManager.default.removeItem(at: link)
        }
    }
}
