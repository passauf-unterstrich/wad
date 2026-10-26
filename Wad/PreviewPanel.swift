// PreviewPanel.swift
// Das Vorschau-Fenster für „Zwischenablage mit Vorschau“ (SPEC 1.10). Zeigt live, was man diktiert:
// fertigen Text normal, vorläufigen grau dahinter. Hängt unter Wads Symbol in der Menüleiste,
// liegt über allem, auch über Apps im Vollbild, und nimmt der App, in der man gerade ist, nicht
// den Fokus. Ein gewöhnliches eigenes Fenster, dafür braucht Wad keine Berechtigung.
// Ist das Diktat fertig, lässt sich der Text darin noch korrigieren, bevor man ihn kopiert.

import SwiftUI

final class PreviewPanel {
    /// Was das Fenster zeigt. Liegt nur im Arbeitsspeicher, wie alle Diktate (SPEC 2.4).
    final class Content: ObservableObject {
        @Published var text = ""
        @Published var draft = ""
        @Published var isListening = false
        @Published var isCopied = false
    }

    static let width: CGFloat = 360
    /// Abstand zur Menüleiste.
    private static let gap: CGFloat = 6

    /// Legt den Text erneut in die Zwischenablage, über den Knopf im Fenster.
    var onCopy: ((String) -> Void)?
    /// Das Diktat, dessen Text das Fenster gerade zeigt.
    private(set) var dictation: Int?

    private let content = Content()
    private var panel: NSPanel?
    private var copiedReset: DispatchWorkItem?

    /// Eine Aufnahme beginnt. Sichtbar wird das Fenster erst, wenn sie kein versehentlicher
    /// Tipper war, sonst blitzte es bei jedem kurzen Antippen auf.
    func begin(dictation: Int) {
        self.dictation = dictation
        content.text = ""
        content.draft = ""
        content.isListening = true
        setCopied(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + DictationController.minDuration) { [weak self] in
            guard let self, self.dictation == dictation, content.isListening else { return }
            show()
        }
    }

    /// Ein fertiges Stück. Der vorläufige Text davor ist damit erledigt.
    func append(_ text: String, dictation: Int) {
        guard dictation == self.dictation else { return }
        content.text += text
        content.draft = ""
    }

    func showDraft(_ draft: String, dictation: Int) {
        guard dictation == self.dictation else { return }
        content.draft = draft
    }

    /// Das Diktat ist fertig. `isCopied` sagt, ob der Text schon in der Zwischenablage liegt.
    func finish(text: String, isCopied: Bool, dictation: Int) {
        guard dictation == self.dictation else { return }
        content.text = text
        content.draft = ""
        content.isListening = false
        setCopied(isCopied)
    }

    /// Alles umgewandelt. Kam dabei kein Text heraus (nur Stille, abgebrochen oder nur angetippt),
    /// verschwindet das Fenster wieder, statt leer stehen zu bleiben.
    func settle() {
        guard content.isListening else { return }
        content.isListening = false
        content.draft = ""
        if content.text.isEmpty { close() }
    }

    func close() {
        dictation = nil
        content.isListening = false
        panel?.orderOut(nil)
    }

    private func setCopied(_ copied: Bool) {
        copiedReset?.cancel()
        content.isCopied = copied
        guard copied else { return }
        let reset = DispatchWorkItem { [weak self] in self?.content.isCopied = false }
        copiedReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reset)
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        // Auf jedem Schreibtisch und über Vollbild-Apps, nicht in Mission Control oder beim App-Wechsel.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Wad ist nie die aktive App. Ohne das verschwände das Fenster sofort wieder.
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let view = PreviewView(content: content,
                               onClose: { [weak self] in self?.close() },
                               onCopy: { [weak self] in
                                   guard let self, !content.text.isEmpty else { return }
                                   onCopy?(content.text)
                                   setCopied(true)
                               },
                               onResize: { [weak self, weak panel] size in
                                   guard let self, let panel else { return }
                                   panel.setContentSize(size)
                                   place(panel)
                               })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []          // die Größe setzt `onResize`, damit das Fenster oben hängen bleibt
        panel.contentView = hosting
        return panel
    }

    /// Mittig unter Wads Symbol. Ist das Symbol nicht zu finden, oben rechts unter der Menüleiste.
    /// Ist die Menüleiste ausgeblendet (Vollbild), knapp unter dem oberen Bildschirmrand.
    private func place(_ panel: NSPanel) {
        let size = panel.frame.size
        let icon = NSApp.windows.first { $0.className == "NSStatusBarWindow" }?.frame
        let screen = icon.flatMap { icon in NSScreen.screens.first { $0.frame.intersects(icon) } } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let top = min(icon?.minY ?? .infinity, visible.maxY) - Self.gap
        let preferredX = icon.map { $0.midX - size.width / 2 } ?? visible.maxX - size.width
        let x = min(max(preferredX, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
    }
}

/// Darf Tastatur-Fokus bekommen, damit man Text darin markieren kann, aber nur auf Klick.
/// Wad wird dabei nicht zur aktiven App.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct PreviewView: View {
    @ObservedObject var content: PreviewPanel.Content
    let onClose: () -> Void
    let onCopy: () -> Void
    let onResize: (CGSize) -> Void

    /// Ab dieser Höhe scrollt der Text und zeigt immer das Ende.
    private static let maxTextHeight: CGFloat = 220
    /// So hoch ist der Textbereich mindestens: Drei bis vier Zeilen sind sofort überblickbar.
    private static let minTextHeight: CGFloat = 72
    @State private var textHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Schließen")

            if isEditable {
                editor
            } else {
                ScrollViewReader { scroller in
                    ScrollView {
                        text
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
                            .id("Ende")
                    }
                    .scrollIndicators(.never)
                    .frame(height: min(max(textHeight, Self.minTextHeight), Self.maxTextHeight))
                    .onPreferenceChange(HeightKey.self) { textHeight = $0 }
                    .onChange(of: content.text + content.draft) { scroller.scrollTo("Ende", anchor: .bottom) }
                }
            }

            HStack {
                Spacer()
                Button(content.isCopied ? "Kopiert ✓" : "In Zwischenablage kopieren", action: onCopy)
                    .controlSize(.small)
                    .disabled(content.isListening || content.text.isEmpty)
            }
        }
        .padding(14)
        .frame(width: PreviewPanel.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(GeometryReader { Color.clear.preference(key: SizeKey.self, value: $0.size) })
        .onPreferenceChange(SizeKey.self, perform: onResize)
    }

    /// Bearbeiten erst nach dem Diktat. Solange Wad noch schreibt, würde es die Korrekturen überschreiben.
    private var isEditable: Bool { !content.isListening && !content.text.isEmpty }

    /// Korrigierbarer Text, gleich groß wie die Vorschau. Gemessen wird an einem unsichtbaren Text,
    /// weil das Eingabefeld seine Höhe nicht selbst meldet. Eine Korrektur macht „Kopiert ✓“ ungültig.
    /// Unter „Letzte Diktate“ bleibt der ursprüngliche Text.
    private var editor: some View {
        TextEditor(text: Binding(get: { content.text }, set: { content.text = $0; content.isCopied = false }))
            .font(.body)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .padding(.horizontal, -5)       // das Eingabefeld rückt Text um 5 Punkte ein, die Vorschau nicht
            .frame(height: min(max(textHeight, Self.minTextHeight), Self.maxTextHeight))
            .background(alignment: .top) {
                Text(content.text + " ")
                    .padding(.horizontal, 5)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
            }
            .onPreferenceChange(HeightKey.self) { textHeight = $0 }
    }

    /// Fertiger Text normal, vorläufiger grau dahinter. Solange noch nichts da ist, ein leiser Hinweis.
    private var text: Text {
        if content.text.isEmpty && content.draft.isEmpty {
            return Text(content.isListening ? "Ich höre zu …" : "").foregroundStyle(.tertiary)
        }
        let draft = content.draft.isEmpty || content.text.isEmpty ? content.draft : " " + content.draft
        return Text(content.text) + Text(draft).foregroundStyle(.secondary)
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct SizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
