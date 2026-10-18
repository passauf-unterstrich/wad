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
                Section("Letztes Diktat") {
                    Text(transcript)
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

    private var menuBarIcon: Image {
        if model.dictationState == .recording { return Image(nsImage: MenuBarIcon.recording) }
        return Image(nsImage: model.isEnabled ? MenuBarIcon.enabled : MenuBarIcon.disabled)
    }
}
