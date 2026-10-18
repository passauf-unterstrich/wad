// WadMain.swift
// Startpunkt von Wad. Die App enthält Code für Apple-Chips und für Intel („Universal“). Der
// Intel-Teil macht nur eines: einen verständlichen Hinweis zeigen und sich beenden. Mikrofon,
// Taste und Modell werden dort nie angefasst (SPEC 2.8).

import AppKit

@main
enum WadMain {
    static func main() {
        #if arch(x86_64)
        showIntelNotice()
        #else
        WadApp.main()
        #endif
    }
}

#if arch(x86_64)
private func showIntelNotice() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let alert = NSAlert()
    alert.messageText = "Wad braucht einen Mac mit Apple-Chip"
    // Auch ein M-Mac landet hier, wenn Wad über Rosetta geöffnet wurde. Dann hilft ein Haken.
    if isRunningUnderRosetta {
        alert.informativeText = "Wad wurde über Rosetta geöffnet. Wähle Wad im Finder aus, öffne mit Cmd+I die Informationen und entferne den Haken bei „Mit Rosetta öffnen“."
    } else {
        alert.informativeText = "Wad funktioniert nur auf Macs mit M1-Chip oder neuer. Dieser Mac hat einen Intel-Prozessor."
    }
    app.activate(ignoringOtherApps: true)
    alert.runModal()
}

private var isRunningUnderRosetta: Bool {
    var translated: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
}
#endif
