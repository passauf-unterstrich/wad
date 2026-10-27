// WadApp.swift
// Wads Oberfläche: das Symbol in der Menüleiste und das Menü darunter. Gestartet wird sie von WadMain.

import SwiftUI

struct WadApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            if let notice = model.notice {
                Text(notice)
                Divider()
            }
            if let update = model.availableUpdate {
                Button("Update verfügbar: \(update.version.description) …") { model.showUpdate() }
                Divider()
            }
            Toggle("Diktieren", isOn: $model.isEnabled)
            // Freies Diktieren: läuft ohne gehaltene Taste, bis man es stoppt oder die Höchstdauer erreicht ist.
            Button(model.isHandsFreeRecording ? "Freies Diktieren stoppen" : "Freies Diktieren starten", action: model.toggleHandsFree)
                .disabled(!model.isEnabled || (model.dictationState == .recording && !model.isHandsFreeRecording))
            // Oben, weil man ihn oft umstellt.
            Picker("Einfügemodus", selection: $model.insertMode) {
                Text("Während des Diktats").tag(InsertMode.whileDictating)
                Text("Nach dem Diktat").tag(InsertMode.afterDictating)
                Divider()
                Text("Nur in die Zwischenablage").tag(InsertMode.clipboard)
                Text("Zwischenablage mit Vorschau").tag(InsertMode.clipboardPreview)
            }
            Divider()
            // Untermenüs statt langer Zeilen: Das Hauptmenü bleibt schmal,
            // macOS klappt die Listen zur Seite auf, an der Platz ist.
            historyMenu("Letzte Diktate", isOn: $model.keepsDictations, entries: model.dictations.entries,
                        empty: "Noch keine Diktate", clear: "Diktate löschen",
                        onClear: model.clearDictations)
            historyMenu("Zwischenablage-Verlauf", isOn: $model.keepsClipboard, entries: model.clipboard.entries,
                        empty: "Noch nichts kopiert", clear: "Verlauf löschen",
                        onClear: model.clearClipboardHistory)
            Divider()
            Picker("Sprache", selection: $model.language) {
                ForEach(AppModel.languages, id: \.code) { language in
                    Text(language.name).tag(language.code)
                }
                Divider()
                Text("Sprachoffen").tag("auto")
            }
            Toggle("Kleinschreibung", isOn: $model.isLowercase)
            Picker("Höchstdauer freies Diktieren", selection: $model.handsFreeMinutes) {
                Text("2 Minuten").tag(2)
                Text("5 Minuten").tag(5)
                Text("10 Minuten").tag(10)
            }
            Menu("Vokabeln") {
                Button("Wort korrigieren …", action: model.openCorrection)
                    .keyboardShortcut("w", modifiers: [.control, .option])
                Button("Vokabelliste im Finder zeigen", action: model.revealVocabularyFile)
                Button("Vorlage für deine KI kopieren", action: model.copyVocabularyPrompt)
            }
            Menu("Fenstermanager") {
                Toggle("Eingeschaltet", isOn: $model.isWindowManagerEnabled)
                Button("Kürzel …", action: model.openShortcutsPanel)
            }
            // Alles zu Updates in einem Untermenü, damit das Hauptmenü kurz bleibt.
            Menu("Updates") {
                Toggle("Automatisch suchen", isOn: $model.checksForUpdates)
                Button("Jetzt suchen …", action: model.checkForUpdatesNow)
                Divider()
                Button("Was ist neu …", action: model.openWhatsNew)
            }
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
            Toggle("Bei Anmeldung starten", isOn: $model.launchesAtLogin)
            Button("Wad beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            menuBarIcon
        }
    }

    /// Ein Verlauf als Untermenü. Ein Klick legt den vollen Text in die Zwischenablage.
    /// Der Schalter oben bestimmt, ob überhaupt mitgeschrieben wird. Er sitzt im Untermenü,
    /// damit das Hauptmenü nicht länger wird.
    private func historyMenu(_ title: String, isOn: Binding<Bool>, entries: [String], empty: String,
                             clear: String, onClear: @escaping () -> Void) -> some View {
        Menu(title) {
            Toggle("Mitschreiben", isOn: isOn)
            Divider()
            if !isOn.wrappedValue {
                Text("Ausgeschaltet")
            } else if entries.isEmpty {
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
        let icon: NSImage
        switch model.dictationState {
        case .recording: icon = MenuBarIcon.recording
        case .processing: icon = MenuBarIcon.processing
        case .idle where model.notice != nil: icon = MenuBarIcon.notice
        case .idle: icon = model.isEnabled ? MenuBarIcon.enabled : MenuBarIcon.disabled
        }
        return Image(nsImage: icon)
    }
}
