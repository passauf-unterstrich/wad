// ShortcutsPanel.swift
// Das kleine Fenster „Fenster-Kürzel …“ (SPEC 1.8): eine Zeile pro Aktion. Klick auf das Kürzel,
// neue Kombination drücken, fertig. Gelesen wird dabei nur, was in diesem Fenster getippt wird.

import Carbon.HIToolbox
import SwiftUI

final class ShortcutsPanel {
    private var panel: NSPanel?

    /// Die Menüsprache hat gewechselt. Den Inhalt zeichnet SwiftUI von selbst neu, nur den Titel nicht.
    func refreshTitle() {
        panel?.title = L10n.t("shortcuts.window")
    }

    func show(manager: WindowManager) {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L10n.t("shortcuts.window")
        panel.isReleasedWhenClosed = false
        let content = NSHostingController(rootView: ShortcutsView(manager: manager))
        content.sizingOptions = .preferredContentSize
        panel.contentViewController = content
        panel.setContentSize(content.view.fittingSize)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

private struct ShortcutsView: View {
    let manager: WindowManager
    @State private var shortcuts: [WindowAction: KeyCombo] = [:]
    @State private var recording: WindowAction?
    @State private var message: String?
    @State private var monitor: Any?
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    GridRow {
                        Text(action.title).gridColumnAlignment(.trailing)
                        Button(recording == action ? L10n.t("shortcuts.press") : shortcuts[action]?.displayName ?? "–") {
                            startRecording(action)
                        }
                        .frame(minWidth: 170)
                    }
                }
            }
            Text(message ?? L10n.t("shortcuts.hint"))
                .font(.callout)
                .foregroundStyle(message == nil ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.t("shortcuts.reset")) {
                    manager.resetToDefaults()
                    shortcuts = manager.shortcuts
                    message = nil
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { shortcuts = manager.shortcuts }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording(_ action: WindowAction) {
        stopRecording()
        recording = action
        message = nil
        manager.isRecordingShortcut = true
        // Lokal heißt: nur Tasten, die in diesem Fenster gedrückt werden, nie in anderen Apps.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: action)
            return nil
        }
    }

    private func handle(_ event: NSEvent, for action: WindowAction) {
        // Erst die Aufnahme beenden, damit die Kürzel wieder angemeldet sind und die Prüfung,
        // ob macOS die neue Kombination hergibt, stimmt.
        stopRecording()
        if event.keyCode == UInt16(kVK_Escape) { return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.subtracting(.shift).isEmpty else {
            message = L10n.t("shortcuts.needsModifier")
            return
        }
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        let combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: UInt32(modifiers))
        message = manager.setShortcut(combo, for: action)
        shortcuts = manager.shortcuts
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        manager.isRecordingShortcut = false
    }
}
