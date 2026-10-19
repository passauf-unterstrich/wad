// ShortcutsPanel.swift
// Das kleine Fenster „Fenster-Kürzel …“ (SPEC 1.8): eine Zeile pro Aktion. Klick auf das Kürzel,
// neue Kombination drücken, fertig. Gelesen wird dabei nur, was in diesem Fenster getippt wird.

import Carbon.HIToolbox
import SwiftUI

final class ShortcutsPanel {
    private var panel: NSPanel?

    func show(manager: WindowManager) {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Fenster-Kürzel"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(WindowAction.allCases, id: \.self) { action in
                    GridRow {
                        Text(action.title).gridColumnAlignment(.trailing)
                        Button(recording == action ? "Kombination drücken …" : shortcuts[action]?.displayName ?? "–") {
                            startRecording(action)
                        }
                        .frame(minWidth: 170)
                    }
                }
            }
            Text(message ?? "Klicke auf ein Kürzel und drücke die neue Kombination. Esc bricht ab.")
                .font(.callout)
                .foregroundStyle(message == nil ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Standard wiederherstellen") {
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
        // Lokal heißt: nur Tasten, die in diesem Fenster gedrückt werden, nie in anderen Apps.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: action)
            return nil
        }
    }

    private func handle(_ event: NSEvent, for action: WindowAction) {
        defer { stopRecording() }
        if event.keyCode == UInt16(kVK_Escape) { return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.subtracting(.shift).isEmpty else {
            message = "Bitte mit ⌘, ⌥ oder ⌃ kombinieren, sonst stört das Kürzel beim Tippen."
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
    }
}
