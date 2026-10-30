// MoveToApplications.swift
// Wer Wad direkt aus der geöffneten DMG startet, statt es in den Programme-Ordner zu ziehen,
// bekommt eine Rückfrage. Aus der DMG heraus würde Wad nach dem Auswerfen verschwinden, und
// der Start bei der Anmeldung ließe sich nicht einrichten.

import AppKit
import DiskArbitration

enum MoveToApplications {
    /// Ganz am Anfang aufrufen, noch vor Berechtigungen und Menüleiste. Tut nichts, wenn Wad schon
    /// richtig liegt. Rückgabe `true` heißt: Die Kopie in Programme ist gestartet, diese Instanz endet.
    static func offerIfNeeded() -> Bool {
        let current = Bundle.main.bundleURL
        guard current.path.hasPrefix("/Volumes/") else { return false }
        NSApplication.shared.setActivationPolicy(.accessory)

        let alert = NSAlert()
        alert.messageText = L10n.t("move.title")
        alert.informativeText = L10n.t("move.text")
        alert.addButton(withTitle: L10n.t("move.confirm"))
        alert.addButton(withTitle: L10n.t("common.notNow"))
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
            failed.messageText = L10n.t("move.failed.title")
            failed.informativeText = L10n.t("move.failed.text")
            failed.addButton(withTitle: L10n.t("common.ok"))
            failed.runModal()
            return false
        }

        // Die Kopie im Programme-Ordner übernimmt, diese Instanz aus der DMG beendet sich.
        return NSWorkspace.shared.open(target)
    }
}

/// Nach dem Installieren hängt das Laufwerk „Wad“ noch in der Finder-Seitenleiste. Läuft Wad aus dem
/// Programme-Ordner, wirft es dieses Laufwerk selbst aus (SPEC „Geplant für 1.1.0“). Ausgeworfen wird nur,
/// was sicher das Wad-Installationsabbild ist. Klappt es nicht, bleibt es still.
enum InstallerVolumeEject {
    /// Einmal beim Start aufrufen. Wartet kurz, damit der Finder das Abbild nach dem Kopieren loslässt.
    static func runSoon() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            installerVolumes().forEach(eject)
        }
    }

    private static func installerVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsReadOnlyKey, .volumeIsLocalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                           options: [.skipHiddenVolumes]) ?? []
        let ownVolume = try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeURLKey]).volume
        return volumes.filter { volume in
            guard volume.path.hasPrefix("/Volumes/"), volume != ownVolume, isMountedByCurrentUser(volume),
                  let values = try? volume.resourceValues(forKeys: Set(keys)),
                  values.volumeIsReadOnly == true, values.volumeIsLocal == true,
                  isDiskImage(volume) else { return false }
            let app = volume.appendingPathComponent("Wad.app")
            return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
    }

    /// Nur Laufwerke, die dieser Benutzer selbst geöffnet hat. Das Abbild eines anderen Benutzers am selben Mac
    /// auszuwerfen, bräuchte Administratorrechte, und macOS fragte dann im Namen von Wad nach dem Passwort.
    private static func isMountedByCurrentUser(_ volume: URL) -> Bool {
        var info = statfs()
        guard statfs(volume.path, &info) == 0 else { return false }
        return info.f_owner == getuid()
    }

    /// Nur eingebundene Disk-Images, nie ein echtes Laufwerk wie ein USB-Stick.
    private static func isDiskImage(_ volume: URL) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volume as CFURL),
              let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return false }
        return (description[kDADiskDescriptionDeviceModelKey] as? String)?
            .trimmingCharacters(in: .whitespaces) == "Disk Image"
    }

    private static func eject(_ volume: URL) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            log.notice("Installations-Laufwerk ausgeworfen")
        } catch {
            // Etwa weil noch ein Finder-Fenster darauf offen ist. Dann bleibt es einfach eingebunden.
            log.notice("Installations-Laufwerk nicht ausgeworfen: \(error.localizedDescription, privacy: .public)")
        }
    }
}
