// WadApp.swift
// Einstiegspunkt von Wad: legt das Symbol in der Menüleiste an und beschreibt das Menü darunter.

import SwiftUI

@main
struct WadApp: App {
    /// Ob Wad auf die Diktier-Taste reagiert. Lebt nur im Arbeitsspeicher, nach jedem Start ist es an.
    @State private var isEnabled = true

    var body: some Scene {
        MenuBarExtra("Wad", systemImage: isEnabled ? "mic" : "mic.slash") {
            Toggle("Diktieren", isOn: $isEnabled)
            Divider()
            Button("Wad beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
