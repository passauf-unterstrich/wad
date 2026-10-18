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
        if model.isKeyHeld { return Image(nsImage: Self.recordingIcon) }
        return Image(systemName: model.isEnabled ? "mic" : "mic.slash")
    }

    /// Roter Kreis. Menüleisten-Symbole sind sonst einfarbig („Template“), deshalb wird er
    /// als farbiges Bild erzeugt und ausdrücklich nicht als Template markiert.
    private static let recordingIcon: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Wad nimmt auf")!
            .withSymbolConfiguration(config)!
        image.isTemplate = false
        return image
    }()
}
