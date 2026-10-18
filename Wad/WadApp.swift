// WadApp.swift
// Einstiegspunkt von Wad: legt das Symbol in der Menüleiste an und beschreibt das Menü darunter.

import SwiftUI

@main
struct WadApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            Toggle("Diktieren", isOn: $model.isEnabled)
            Divider()
            if !model.hasAccessibility {
                Button("Bedienungshilfen erlauben …") {
                    Permissions.openAccessibilitySettings()
                }
                Divider()
            }
            Button("Wad beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            menuBarIcon
        }
    }

    private var menuBarIcon: Image {
        if model.isKeyHeld { return Image(nsImage: MenuBarIcon.recording) }
        return Image(nsImage: model.isEnabled ? MenuBarIcon.enabled : MenuBarIcon.disabled)
    }
}
