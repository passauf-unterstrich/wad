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
            if let transcript = model.lastTranscript {
                // Ein Untermenü statt einer langen Zeile: Das Hauptmenü bleibt schmal,
                // macOS klappt die Liste zur Seite auf, an der Platz ist.
                Menu("Letzte Diktate") {
                    Text(Self.menuTitle(for: transcript))
                }
                Divider()
            }
            if model.isTranscriberReady == false {
                Text("Spracherkennung nicht verfügbar")
                Divider()
            }
            if !model.hasMicrophone {
                Button("Mikrofon erlauben …") {
                    Permissions.openMicrophoneSettings()
                }
            }
            if !model.hasAccessibility {
                Button("Bedienungshilfen erlauben …") {
                    Permissions.openAccessibilitySettings()
                }
            }
            if !model.hasMicrophone || !model.hasAccessibility {
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

    /// Kürzt einen Text auf eine Menüzeile: einzeilig, höchstens 50 Zeichen.
    private static func menuTitle(for text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > 50 ? line.prefix(49).trimmingCharacters(in: .whitespaces) + "…" : line
    }

    private var menuBarIcon: Image {
        if model.dictationState == .recording { return Image(nsImage: MenuBarIcon.recording) }
        return Image(nsImage: model.isEnabled ? MenuBarIcon.enabled : MenuBarIcon.disabled)
    }
}
