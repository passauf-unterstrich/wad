// CorrectionPanel.swift
// Das kleine Fenster zum Korrigieren: oben das falsch Erkannte, darunter die richtige Schreibweise,
// unten die Wahl, ob Wad sich das nur bis zum Neustart oder dauerhaft merkt.

import SwiftUI

final class CorrectionPanel {
    private var panel: NSPanel?

    /// Die Menüsprache hat gewechselt. Den Inhalt zeichnet SwiftUI von selbst neu, nur den Titel nicht.
    func refreshTitle() {
        panel?.title = L10n.t("correction.window")
    }

    /// Öffnet das Fenster vor allen anderen. `onSave` bekommt den Eintrag und ob er dauerhaft gilt.
    func show(wrong: String, onSave: @escaping (Vocabulary.Entry, Bool) -> Void) {
        panel?.close()
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L10n.t("correction.window")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        // Die Fenstergröße richtet sich nach dem Inhalt, statt fest vorgegeben zu sein.
        let content = NSHostingController(rootView: CorrectionView(wrong: wrong) { [weak panel] entry, permanently in
            if let entry { onSave(entry, permanently) }
            panel?.close()
        })
        content.sizingOptions = .preferredContentSize
        panel.contentViewController = content
        panel.setContentSize(content.view.fittingSize)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

struct CorrectionView: View {
    @State private var wrong: String
    @State private var right = ""
    @FocusState private var focusedField: Field?
    @ObservedObject private var l10n = L10n.shared
    /// `nil` heißt abgebrochen.
    let finish: (Vocabulary.Entry?, Bool) -> Void

    private enum Field { case wrong, right }

    init(wrong: String, finish: @escaping (Vocabulary.Entry?, Bool) -> Void) {
        _wrong = State(initialValue: wrong)
        self.finish = finish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.t("correction.recognized")).gridColumnAlignment(.trailing)
                    TextField("", text: $wrong)
                        .focused($focusedField, equals: .wrong)
                }
                GridRow {
                    Text(L10n.t("correction.right"))
                    TextField("", text: $right)
                        .focused($focusedField, equals: .right)
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button(L10n.t("common.cancel"), role: .cancel) { finish(nil, false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Group {
                    Button(L10n.t("correction.untilRestart")) { save(permanently: false) }
                    Button(L10n.t("correction.always")) { save(permanently: true) }
                        .keyboardShortcut(.defaultAction)
                }
                .disabled(right.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { focusedField = wrong.isEmpty ? .wrong : .right }
    }

    private func save(permanently: Bool) {
        let wrong = wrong.trimmingCharacters(in: .whitespaces)
        let right = right.trimmingCharacters(in: .whitespaces)
        finish(Vocabulary.Entry(wrong: wrong.isEmpty ? nil : wrong, right: right), permanently)
    }
}
