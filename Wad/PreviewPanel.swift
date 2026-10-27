// PreviewPanel.swift
// Das Vorschau-Fenster für „Zwischenablage mit Vorschau“ und freies Diktieren (SPEC 1.10): ein kleiner
// Notizzettel. Zeigt live, was man diktiert, fertigen Text normal, vorläufigen grau dahinter. Der fertige
// Text lässt sich schon während des Diktats korrigieren, jedes weitere Diktat kommt auf denselben Zettel.
// „Einfügen“ bringt den Zettel in die App, in der man vorher war, und beginnt einen neuen.
// Hängt unter Wads Symbol in der Menüleiste, liegt über allem, auch über Apps im Vollbild, und nimmt der
// App, in der man gerade ist, nicht den Fokus. Ein gewöhnliches eigenes Fenster, dafür braucht Wad keine
// Berechtigung. Was man in dieses Fenster tippt, sieht Wad wie jede App ihr eigenes Textfeld, nie mehr.

import SwiftUI

final class PreviewPanel {
    /// Was das Fenster zeigt. Liegt nur im Arbeitsspeicher, wie alle Diktate (SPEC 2.4).
    final class Content: ObservableObject {
        @Published var isListening = false
        @Published var isCopied = false
        @Published var isEmpty = true
        @Published var hasDraft = false
        @Published var textHeight: CGFloat = 0
        /// Frühere Zettel aus „Letzte Diktate“, neuester zuerst. Leer, wenn dort nicht mitgeschrieben wird.
        @Published var history: [String] = []
        /// Welcher frühere Zettel gerade gezeigt wird. `nil` ist der aktuelle.
        @Published var historyIndex: Int?
    }

    static let width: CGFloat = 360
    /// Abstand zur Menüleiste.
    private static let gap: CGFloat = 6

    /// Legt einen Text in die Zwischenablage, über den Knopf im Fenster.
    var onCopy: ((String) -> Void)?
    /// Fügt einen Text in die App `target` ein. Meldet über `done`, ob es geklappt hat.
    var onPaste: ((_ text: String, _ target: NSRunningApplication?, _ done: @escaping (Bool) -> Void) -> Void)?
    /// Ein Zettel soll unter „Letzte Diktate“: `old` ist seine dort schon abgelegte frühere Fassung.
    var onStore: ((_ old: String?, _ new: String) -> Void)?
    /// Bittet darum, eine laufende Aufnahme zu beenden, bevor eingefügt oder geschlossen wird.
    var onStopRequest: (() -> Void)?
    /// Das Diktat, das gerade auf den Zettel schreibt.
    private(set) var dictation: Int?

    /// Frühere Zettel, wie sie unter „Letzte Diktate“ stehen.
    var history: [String] {
        get { content.history }
        set {
            content.history = newValue
            if let index = content.historyIndex, index >= newValue.count { content.historyIndex = nil }
        }
    }

    /// Der Text des Zettels ohne den grauen, vorläufigen Teil.
    var pageText: String { page.pageText }

    /// Hat der Nutzer in das Fenster geklickt? Dann gehört auch die nächste Aufnahme hierher.
    var isFocused: Bool { panel?.isKeyWindow == true }

    private let content = Content()
    private let page = PageTextView()
    private var panel: NSPanel?
    private var copiedReset: DispatchWorkItem?
    /// Die Fassung dieses Zettels, die schon unter „Letzte Diktate“ liegt.
    private var storedText: String?
    /// Was nach dem Ende der laufenden Aufnahme passieren soll.
    private var pending: PendingAction?

    private enum PendingAction {
        case paste(NSRunningApplication?)
        case close
    }

    init() {
        page.onChange = { [weak self] in self?.pageChanged() }
    }

    /// Eine Aufnahme beginnt. Ihr Text kommt an die Cursor-Stelle, wenn man gerade im Fenster ist,
    /// sonst ans Ende. Sichtbar wird das Fenster erst, wenn sie kein versehentlicher Tipper war,
    /// sonst blitzte es bei jedem kurzen Antippen auf.
    func begin(dictation: Int) {
        if case .close = pending { finishClose() }
        pending = nil
        self.dictation = dictation
        content.historyIndex = nil
        content.isListening = true
        setCopied(false)
        page.beginDictation(atCursor: isFocused && panel?.firstResponder === page)
        DispatchQueue.main.asyncAfter(deadline: .now() + DictationController.minDuration) { [weak self] in
            guard let self, self.dictation == dictation, content.isListening, pending == nil else { return }
            show()
        }
    }

    /// Ein fertiges Stück. Der vorläufige Text davor ist damit erledigt.
    func append(_ text: String, dictation: Int) {
        guard dictation == self.dictation else { return }
        page.appendFinal(text)
    }

    func showDraft(_ draft: String, dictation: Int) {
        guard dictation == self.dictation, content.isListening else { return }
        page.setDraft(draft)
    }

    /// Das Diktat ist fertig. `isCopied` sagt, ob der Zettel schon in der Zwischenablage liegt.
    func finish(isCopied: Bool, dictation: Int) {
        guard dictation == self.dictation else { return }
        page.setDraft("")
        content.isListening = false
        setCopied(isCopied)
    }

    /// Keine Aufnahme mehr. Kam kein Text auf den Zettel (nur Stille, abgebrochen oder nur angetippt),
    /// verschwindet das Fenster wieder, statt leer stehen zu bleiben. Wartet „Einfügen“ oder ✕ auf das
    /// Ende der Aufnahme, geht es jetzt weiter.
    func settle() {
        if content.isListening {
            content.isListening = false
            page.setDraft("")
        }
        switch pending {
        case .paste(let target):
            pending = nil
            paste(pageText, into: target, clearsPage: true)
        case .close:
            finishClose()
        case nil:
            if page.pageText.isEmpty { panel?.orderOut(nil) }
        }
    }

    /// Schließt das Fenster. Der Zettel kommt unter „Letzte Diktate“, der nächste beginnt leer.
    /// Läuft noch eine Aufnahme, endet sie zuerst, und ihr Text kommt noch mit auf den Zettel.
    func close() {
        panel?.orderOut(nil)
        if content.isListening {
            pending = .close
            onStopRequest?()
        } else {
            finishClose()
        }
    }

    private func finishClose() {
        pending = nil
        store()
        clearPage()
    }

    /// Legt den Zettel unter „Letzte Diktate“ ab. Eine frühere Fassung desselben Zettels wird ersetzt.
    private func store() {
        let text = pageText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text != storedText else { return }
        onStore?(storedText, text)
        storedText = text
    }

    private func clearPage() {
        dictation = nil
        storedText = nil
        content.historyIndex = nil
        setCopied(false)
        page.reset()
    }

    /// Knopf „Einfügen“. Ziel ist die App, die vorne ist: Wads Fenster nimmt ihr den Fokus nie ab.
    /// Läuft noch eine Aufnahme, endet sie zuerst, eingefügt wird mit ihrem letzten Wort.
    private func pasteTapped() {
        let target = NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
        if let index = content.historyIndex, index < content.history.count {
            paste(content.history[index], into: target, clearsPage: false)
        } else if content.isListening {
            pending = .paste(target)
            panel?.orderOut(nil)
            onStopRequest?()
        } else {
            paste(pageText, into: target, clearsPage: true)
        }
    }

    /// Das Fenster geht weg, damit die Ziel-App den Tastendruck bekommt. Klappt das Einfügen nicht,
    /// etwa in einem Passwortfeld, bleibt der Zettel, wie er ist, und das Fenster kommt wieder.
    private func paste(_ text: String, into target: NSRunningApplication?, clearsPage: Bool) {
        guard !text.isEmpty else { return }
        panel?.orderOut(nil)
        content.historyIndex = nil
        onPaste?(text, target) { [weak self] pasted in
            guard let self else { return }
            if pasted, clearsPage {
                store()
                clearPage()
            } else if !page.pageText.isEmpty {
                show()
            }
        }
    }

    private func copyTapped() {
        if let index = content.historyIndex, index < content.history.count {
            onCopy?(content.history[index])
        } else {
            guard !pageText.isEmpty else { return }
            onCopy?(pageText)
            store()
        }
        setCopied(true)
    }

    private func pageChanged() {
        content.isEmpty = page.pageText.isEmpty
        content.hasDraft = page.hasDraft
        content.textHeight = page.contentHeight
        // Eine Korrektur macht „Kopiert ✓“ ungültig.
        if page.isUserEdit { content.isCopied = false }
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
        let view = PreviewView(content: content, page: page,
                               onClose: { [weak self] in self?.close() },
                               onCopy: { [weak self] in self?.copyTapped() },
                               onPaste: { [weak self] in self?.pasteTapped() },
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

/// Darf Tastatur-Fokus bekommen, damit man im Zettel schreiben kann, aber nur auf Klick.
/// Wad wird dabei nicht zur aktiven App.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Der Zettel selbst. Fertiger Text ist frei bearbeitbar, der graue vorläufige Text steht an der Stelle,
/// an der das laufende Diktat schreibt, und lässt sich nicht anfassen. Diese Stelle (`anchor`) wandert mit,
/// wenn man davor etwas ändert, und rückt hinter jedes fertige Stück. So landet Diktiertes nie mitten in
/// dem, was man gerade selbst tippt.
final class PageTextView: NSTextView, NSTextViewDelegate, NSTextStorageDelegate {
    /// Meldet jede Änderung an Text oder Höhe.
    var onChange: (() -> Void)?
    /// Kam die letzte Änderung vom Nutzer statt von Wad?
    private(set) var isUserEdit = false

    private var anchor = 0
    private var draftLength = 0
    private var isOwnEdit = false

    private static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private static let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
    private static let draft: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]

    let scrollView = NSScrollView()

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: PreviewPanel.width - 28, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: NSRect(x: 0, y: 0, width: PreviewPanel.width - 28, height: 0), textContainer: container)
        storage.delegate = self
        delegate = self
        isRichText = true                   // nötig für den grauen Teil, eingefügt wird trotzdem nur reiner Text
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = .width
        typingAttributes = Self.normal
        scrollView.documentView = self
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .none
    }

    required init?(coder: NSCoder) { nil }

    /// Fremde Formatierung bleibt draußen: Eingefügt wird immer nur reiner Text.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    var pageText: String {
        let text = string as NSString
        return text.replacingCharacters(in: NSRange(location: anchor, length: draftLength), with: "")
    }

    var hasDraft: Bool { draftLength > 0 }

    var contentHeight: CGFloat {
        guard let layoutManager, let textContainer else { return 0 }
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).height)
    }

    /// Ein neues Diktat schreibt an den Cursor, wenn der Nutzer ihn gesetzt hat, sonst ans Ende.
    func beginDictation(atCursor: Bool) {
        setDraft("")
        let length = (string as NSString).length
        anchor = atCursor ? min(selectedRange().upperBound, length) : length
    }

    func appendFinal(_ text: String) {
        setDraft("")
        let spaced = spaced(text)
        guard !spaced.isEmpty else { return }
        replace(NSRange(location: anchor, length: 0), with: NSAttributedString(string: spaced, attributes: Self.normal))
        anchor += (spaced as NSString).length
        scrollRangeToVisible(NSRange(location: anchor, length: 0))
    }

    func setDraft(_ text: String) {
        let spaced = text.isEmpty ? "" : spaced(text)
        guard draftLength > 0 || !spaced.isEmpty else { return }
        replace(NSRange(location: anchor, length: draftLength), with: NSAttributedString(string: spaced, attributes: Self.draft))
        draftLength = (spaced as NSString).length
        if draftLength > 0 { scrollRangeToVisible(NSRange(location: anchor + draftLength, length: 0)) }
    }

    func reset() {
        replace(NSRange(location: 0, length: (string as NSString).length), with: NSAttributedString())
        anchor = 0
        draftLength = 0
        setSelectedRange(NSRange(location: 0, length: 0))
    }

    /// Setzt bei Bedarf ein Leerzeichen davor und dahinter, damit Diktiertes nicht an Wörtern klebt.
    private func spaced(_ text: String) -> String {
        let all = string as NSString
        let before = anchor > 0 ? all.substring(with: NSRange(location: anchor - 1, length: 1)) : ""
        let afterIndex = anchor + draftLength
        let after = afterIndex < all.length ? all.substring(with: NSRange(location: afterIndex, length: 1)) : ""
        var result = text
        let beforeIsSpace = before.isEmpty || before.first!.isWhitespace
        if beforeIsSpace {
            result = String(result.drop { $0 == " " })
        } else if let first = result.first, !first.isWhitespace, !",.;:!?)".contains(first) {
            result = " " + result
        }
        if let first = after.first, !first.isWhitespace, !",.;:!?)".contains(first),
           let last = result.last, !last.isWhitespace {
            result += " "
        }
        return result
    }

    /// Ändert den Text im Namen von Wad. Der Cursor des Nutzers bleibt, wo er war, und rückt nur weiter,
    /// wenn er hinter der Änderung steht. Rückgängig machen gilt danach nur für die eigenen Änderungen
    /// ab hier, sonst passten die gemerkten Stellen nicht mehr zum Text.
    private func replace(_ range: NSRange, with text: NSAttributedString) {
        guard let textStorage else { return }
        let delta = text.length - range.length
        let selections = selectedRanges.map { $0.rangeValue }.map { selection -> NSRange in
            var selection = selection
            if selection.location >= range.upperBound {
                selection.location += delta
            } else if selection.location > range.location {
                selection = NSRange(location: range.location + text.length, length: 0)
            }
            return selection
        }
        isOwnEdit = true
        textStorage.replaceCharacters(in: range, with: text)
        isOwnEdit = false
        let length = textStorage.length
        setSelectedRanges(selections.map { NSValue(range: NSRange(location: min($0.location, length),
                                                                     length: min($0.length, length - min($0.location, length)))) },
                          affinity: .downstream, stillSelecting: false)
        undoManager?.removeAllActions()
        isUserEdit = false
        onChange?()
    }

    /// Der graue Teil ist tabu. Was davor geändert wird, schiebt die Schreibstelle mit.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard draftLength > 0 else { return true }
        let draftEnd = anchor + draftLength
        if range.length == 0 { return range.location <= anchor || range.location >= draftEnd }
        return range.upperBound <= anchor || range.location >= draftEnd
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard !isOwnEdit, editedMask.contains(.editedCharacters) else { return }
        let oldLength = editedRange.length - delta
        if editedRange.location + oldLength <= anchor { anchor += delta }
    }

    func textDidChange(_ notification: Notification) {
        isUserEdit = true
        onChange?()
    }

    /// Getippter Text ist immer normal, auch direkt vor dem grauen Teil.
    func textViewDidChangeSelection(_ notification: Notification) {
        typingAttributes = Self.normal
    }
}

private struct PreviewView: View {
    @ObservedObject var content: PreviewPanel.Content
    let page: PageTextView
    let onClose: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onResize: (CGSize) -> Void

    /// Ab dieser Höhe scrollt der Text.
    private static let maxTextHeight: CGFloat = 220
    /// So hoch ist der Textbereich mindestens: Drei bis vier Zeilen sind sofort überblickbar.
    private static let minTextHeight: CGFloat = 72
    /// Höhe eines früheren Textes beim Blättern, gemessen wie der Zettel selbst.
    @State private var historyHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Schließen, der Text kommt unter „Letzte Diktate“")
                Spacer()
                if !content.history.isEmpty {
                    arrow("chevron.left", help: "Früherer Text", disabled: (content.historyIndex ?? -1) >= content.history.count - 1) {
                        content.historyIndex = (content.historyIndex ?? -1) + 1
                    }
                    arrow("chevron.right", help: "Neuerer Text", disabled: content.historyIndex == nil) {
                        content.historyIndex = content.historyIndex.flatMap { $0 > 0 ? $0 - 1 : nil }
                    }
                }
            }

            Group {
                if let index = content.historyIndex, index < content.history.count {
                    ScrollView {
                        Text(content.history[index])
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
                    }
                    .onPreferenceChange(HeightKey.self) { historyHeight = $0 }
                    .scrollIndicators(.never)
                } else {
                    PageView(page: page)
                        .overlay(alignment: .topLeading) {
                            if content.isEmpty && !content.hasDraft && content.isListening {
                                Text("Ich höre zu …").foregroundStyle(.tertiary).allowsHitTesting(false)
                            }
                        }
                }
            }
            .frame(height: min(max(content.historyIndex == nil ? content.textHeight : historyHeight, Self.minTextHeight),
                               Self.maxTextHeight))

            HStack {
                Spacer()
                Button(content.isCopied ? "Kopiert ✓" : "Kopieren", action: onCopy)
                    .disabled(!hasText)
                Button("Einfügen", action: onPaste)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help("In die App einfügen, in der du vorher warst (⌘↩)")
                    .disabled(!hasText)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: PreviewPanel.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(GeometryReader { Color.clear.preference(key: SizeKey.self, value: $0.size) })
        .onPreferenceChange(SizeKey.self, perform: onResize)
    }

    private var hasText: Bool { content.historyIndex != nil || !content.isEmpty }

    private func arrow(_ symbol: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .disabled(disabled)
        .help(help)
    }
}

/// Bettet den Zettel in die Oberfläche ein. Es ist immer derselbe, damit Text und Cursor beim Blättern bleiben.
private struct PageView: NSViewRepresentable {
    let page: PageTextView

    func makeNSView(context: Context) -> NSScrollView { page.scrollView }
    func updateNSView(_ view: NSScrollView, context: Context) {}
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct SizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
