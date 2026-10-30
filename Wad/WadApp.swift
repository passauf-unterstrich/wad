// WadApp.swift
// Wads Oberfläche: das Symbol in der Menüleiste und das Menü darunter. Gestartet wird sie von WadMain.

import SwiftUI

struct WadApp: App {
    @StateObject private var model = AppModel()
    @ObservedObject private var l10n = L10n.shared

    var body: some Scene {
        MenuBarExtra {
            if let notice = model.notice {
                Text(notice)
                Divider()
            }
            if let update = model.availableUpdate {
                Button(L10n.t("menu.updateAvailable", update.version.description)) { model.showUpdate() }
                Divider()
            }
            Toggle(L10n.t("menu.dictation"), isOn: $model.isEnabled)
            // Freies Diktieren: läuft ohne gehaltene Taste, bis man es stoppt oder die Höchstdauer erreicht ist.
            Button(L10n.t(model.isHandsFreeRecording ? "menu.handsFree.stop" : "menu.handsFree.start"), action: model.toggleHandsFree)
                .disabled(!model.isEnabled || (model.dictationState == .recording && !model.isHandsFreeRecording))
            // Oben, weil man ihn oft umstellt.
            Picker(L10n.t("menu.insertMode"), selection: $model.insertMode) {
                Text(L10n.t("menu.insertMode.whileDictating")).tag(InsertMode.whileDictating)
                Text(L10n.t("menu.insertMode.afterDictating")).tag(InsertMode.afterDictating)
                Divider()
                Text(L10n.t("menu.insertMode.clipboard")).tag(InsertMode.clipboard)
                Text(L10n.t("menu.insertMode.clipboardPreview")).tag(InsertMode.clipboardPreview)
            }
            Divider()
            // Untermenüs statt langer Zeilen: Das Hauptmenü bleibt schmal,
            // macOS klappt die Listen zur Seite auf, an der Platz ist.
            historyMenu(L10n.t("menu.recentDictations"), isOn: $model.keepsDictations, entries: model.dictations.entries,
                        empty: L10n.t("menu.recentDictations.empty"), clear: L10n.t("menu.recentDictations.clear"),
                        onClear: model.clearDictations)
            historyMenu(L10n.t("menu.clipboardHistory"), isOn: $model.keepsClipboard, entries: model.clipboard.entries,
                        empty: L10n.t("menu.clipboardHistory.empty"), clear: L10n.t("menu.clipboardHistory.clear"),
                        onClear: model.clearClipboardHistory)
            Divider()
            Picker(L10n.t("menu.inputLanguage"), selection: $model.language) {
                ForEach(AppModel.languages, id: \.self) { code in
                    Text(L10n.t("language.\(code)")).tag(code)
                }
                Divider()
                Text(L10n.t("language.auto")).tag("auto")
            }
            Picker(L10n.t("menu.menuLanguage"), selection: $l10n.language) {
                ForEach(MenuLanguage.allCases, id: \.self) { language in
                    Text(language.nativeName).tag(language)
                }
            }
            Toggle(L10n.t("menu.lowercase"), isOn: $model.isLowercase)
            Picker(L10n.t("menu.handsFreeLimit"), selection: $model.handsFreeMinutes) {
                Text(L10n.t("menu.minutes", 2)).tag(2)
                Text(L10n.t("menu.minutes", 5)).tag(5)
                Text(L10n.t("menu.minutes", 10)).tag(10)
            }
            Menu(L10n.t("menu.vocabulary")) {
                Button(L10n.t("menu.vocabulary.correct"), action: model.openCorrection)
                    .keyboardShortcut("w", modifiers: [.control, .option])
                Button(L10n.t("menu.vocabulary.reveal"), action: model.revealVocabularyFile)
                Button(L10n.t("menu.vocabulary.copyPrompt"), action: model.copyVocabularyPrompt)
            }
            Menu(L10n.t("menu.windowManager")) {
                Toggle(L10n.t("menu.windowManager.enabled"), isOn: $model.isWindowManagerEnabled)
                Button(L10n.t("menu.windowManager.shortcuts"), action: model.openShortcutsPanel)
            }
            // Alles zu Updates in einem Untermenü, damit das Hauptmenü kurz bleibt.
            Menu(L10n.t("menu.updates")) {
                Toggle(L10n.t("menu.updates.automatic"), isOn: $model.checksForUpdates)
                Button(L10n.t("menu.updates.checkNow"), action: model.checkForUpdatesNow)
                Divider()
                Button(L10n.t("menu.updates.whatsNew"), action: model.openWhatsNew)
            }
            Divider()
            if model.isTranscriberReady == false {
                Text(L10n.t("menu.speechUnavailable"))
                Divider()
            }
            if !model.hasMicrophone {
                Button(L10n.t("menu.allowMicrophone")) {
                    Permissions.openMicrophoneSettings()
                }
            }
            if !model.hasAccessibility {
                Button(L10n.t("menu.allowAccessibility")) {
                    Permissions.openAccessibilitySettings()
                }
            }
            if !model.hasMicrophone || !model.hasAccessibility {
                Divider()
            }
            Toggle(L10n.t("menu.openAtLogin"), isOn: $model.launchesAtLogin)
            Button(L10n.t("menu.quit")) {
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
            Toggle(L10n.t("menu.history.keep"), isOn: isOn)
            Divider()
            if !isOn.wrappedValue {
                Text(L10n.t("menu.history.off"))
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
        let (icon, description): (NSImage, String)
        switch model.dictationState {
        case .recording: (icon, description) = (MenuBarIcon.recording, L10n.t("icon.recording"))
        case .processing: (icon, description) = (MenuBarIcon.processing, L10n.t("icon.processing"))
        case .idle where model.notice != nil: (icon, description) = (MenuBarIcon.notice, L10n.t("icon.notice"))
        case .idle where model.isEnabled: (icon, description) = (MenuBarIcon.enabled, "Wad")
        case .idle: (icon, description) = (MenuBarIcon.disabled, L10n.t("icon.disabled"))
        }
        icon.accessibilityDescription = description
        return Image(nsImage: icon)
    }
}
