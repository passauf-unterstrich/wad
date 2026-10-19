// CorrectionPanel.swift
// Das kleine Fenster zum Korrigieren: oben das falsch Erkannte, darunter die richtige Schreibweise,
// unten die Wahl, ob Wad sich das nur bis zum Neustart oder dauerhaft merkt.

import SwiftUI

final class CorrectionPanel {
    private var panel: NSPanel?

    /// Öffnet das Fenster vor allen anderen. `onSave` bekommt den Eintrag und ob er dauerhaft gilt.
    func show(wrong: String, onSave: @escaping (Vocabulary.Entry, Bool) -> Void) {
        panel?.close()
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable],
                            backing: .buffered, defer: false)
        panel.title = "Vokabel korrigieren"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: CorrectionView(wrong: wrong) { [weak panel] entry, permanently in
            if let entry { onSave(entry, permanently) }
            panel?.close()
        })
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

private struct CorrectionView: View {
    @State var wrong: String
    @State private var right = ""
    @FocusState private var isRightFocused: Bool
    /// `nil` heißt abgebrochen.
    let finish: (Vocabulary.Entry?, Bool) -> Void

    init(wrong: String, finish: @escaping (Vocabulary.Entry?, Bool) -> Void) {
        _wrong = State(initialValue: wrong)
        self.finish = finish
    }

    var body: some View {
        Form {
            TextField("Erkannt", text: $wrong, prompt: Text("z. B. Watt"))
            TextField("Richtig", text: $right, prompt: Text("z. B. Wad"))
                .focused($isRightFocused)
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Abbrechen", role: .cancel) { finish(nil, false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Group {
                    Button("Nur bis zum Neustart") { save(permanently: false) }
                    Button("Immer merken") { save(permanently: true) }
                        .keyboardShortcut(.defaultAction)
                }
                .disabled(right.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 400)
        .onAppear { isRightFocused = true }
    }

    private func save(permanently: Bool) {
        let wrong = wrong.trimmingCharacters(in: .whitespaces)
        let right = right.trimmingCharacters(in: .whitespaces)
        finish(Vocabulary.Entry(wrong: wrong.isEmpty ? nil : wrong, right: right), permanently)
    }
}
