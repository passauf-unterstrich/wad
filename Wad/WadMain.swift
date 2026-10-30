// WadMain.swift
// Startpunkt von Wad. Die App enthält Code für Apple-Chips und für Intel („Universal“). Der
// Intel-Teil macht nur eines: einen verständlichen Hinweis zeigen und sich beenden. Mikrofon,
// Taste und Modell werden dort nie angefasst (SPEC 2.8).

import AppKit

@main
enum WadMain {
    static func main() {
        _ = L10n.shared     // zuerst: Die Menüsprache entscheidet sich, bevor Wad irgendeine Einstellung anlegt
        #if arch(x86_64)
        showIntelNotice()
        #else
        if MoveToApplications.offerIfNeeded() { return }
        WadApp.main()
        #endif
    }
}

#if arch(x86_64)
private func showIntelNotice() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let alert = NSAlert()
    alert.messageText = L10n.t("intel.title")
    // Auch ein M-Mac landet hier, wenn Wad über Rosetta geöffnet wurde. Dann hilft ein Haken.
    if isRunningUnderRosetta {
        alert.informativeText = L10n.t("intel.rosetta")
    } else {
        alert.informativeText = L10n.t("intel.unsupported")
    }
    alert.addButton(withTitle: L10n.t("common.ok"))
    app.activate(ignoringOtherApps: true)
    alert.runModal()
}

private var isRunningUnderRosetta: Bool {
    var translated: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
}
#endif
