// WadApp.swift
// Einstiegspunkt von Wad: legt das Symbol in der Menüleiste an und beschreibt das Menü darunter.

import SwiftUI

@main
struct WadApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            Toggle("Diktieren", isOn: $model.isEnabled)
            Picker("Modus", selection: $model.mode) {
                Text("Live").tag(DictationController.Mode.live)
                Text("Am Ende einfügen").tag(DictationController.Mode.atEnd)
            }
            Divider()
            // Untermenüs statt langer Zeilen: Das Hauptmenü bleibt schmal,
            // macOS klappt die Listen zur Seite auf, an der Platz ist.
            historyMenu("Letzte Diktate", entries: model.dictations.entries,
                        empty: "Noch keine Diktate", clear: "Diktate löschen",
                        onClear: model.clearDictations)
            historyMenu("Zwischenablage-Verlauf", entries: model.clipboard.entries,
                        empty: "Noch nichts kopiert", clear: "Verlauf löschen",
                        onClear: model.clearClipboardHistory)
            Divider()
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

    /// Ein Verlauf als Untermenü. Ein Klick legt den vollen Text in die Zwischenablage.
    private func historyMenu(_ title: String, entries: [String], empty: String, clear: String,
                             onClear: @escaping () -> Void) -> some View {
        Menu(title) {
            if entries.isEmpty {
                Text(empty)
            }
            ForEach(entries, id: \.self) { entry in
                Button(Self.menuTitle(for: entry)) { model.copyToClipboard(entry) }
            }
            Divider()
            Button(clear, action: onClear)
                .disabled(entries.isEmpty)
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
