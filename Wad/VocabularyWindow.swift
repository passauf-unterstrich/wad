// VocabularyWindow.swift
// Das Fenster „Vokabeln“: die Vokabelliste als Tabelle, „Wad hört“ links, „Wad schreibt“ rechts.
// Es bearbeitet dieselbe Datei Vokabeln.txt wie bisher (VocabularyFile), Zeile für Zeile. Was man nicht anfasst,
// bleibt Zeichen für Zeichen stehen. Jede Änderung wird sofort gespeichert, ⌘Z nimmt sie zurück.

import SwiftUI

final class VocabularyWindow {
    private var window: NSWindow?
    private var editor: VocabularyEditor?

    /// Die Menüsprache hat gewechselt. Den Inhalt zeichnet SwiftUI von selbst neu, nur den Titel nicht.
    func refreshTitle() {
        window?.title = L10n.t("vocabulary.window")
    }

    func show(store: VocabularyStore, onReveal: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            editor?.reload()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let editor = VocabularyEditor(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = L10n.t("vocabulary.window")
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.contentViewController = NSHostingController(rootView: VocabularyView(editor: editor, onReveal: onReveal))
        window.setContentSize(NSSize(width: 640, height: 500))
        window.center()
        // Größe und Platz bleiben bis zum nächsten Öffnen, wie bei jedem Mac-Fenster.
        window.setFrameAutosaveName("Vokabeln")
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.editor = editor
    }
}

/// Hält die Liste fürs Fenster und schreibt jede Änderung sofort in die Datei.
final class VocabularyEditor: ObservableObject {
    @Published private(set) var file: VocabularyFile
    @Published private(set) var sessionEntries: [Vocabulary.Entry] = []
    /// Die Datei gibt es, sie lässt sich aber nicht lesen. Dann zeigt das Fenster nur einen Hinweis und schreibt nie.
    @Published private(set) var isUnreadable = false
    weak var undoManager: UndoManager?

    private let store: VocabularyStore
    private var loadedDate: Date?
    private var timer: Timer?

    init(store: VocabularyStore) {
        self.store = store
        file = VocabularyFile(text: "")
        reload()
        store.onChange = { [weak self] in self?.reload() }
        // Wer die Datei nebenher von Hand oder mit einer KI ändert, sieht das hier sofort.
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.reloadIfChangedOnDisk() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }

    func reload() {
        loadedDate = store.modificationDate
        sessionEntries = store.sessionEntries
        guard let loaded = store.file else {
            isUnreadable = true
            return
        }
        isUnreadable = false
        if loaded.text != file.text { file = loaded }
    }

    private func reloadIfChangedOnDisk() {
        if store.modificationDate != loadedDate { reload() }
    }

    // MARK: Änderungen, jede mit Rückgängig

    func update(at index: Int, wrong: String, right: String) {
        guard file.lines.indices.contains(index), let old = file.lines[index].entry else { return }
        let wrong = wrong.trimmingCharacters(in: .whitespaces)
        let right = right.trimmingCharacters(in: .whitespaces)
        let new = Vocabulary.Entry(wrong: wrong.isEmpty ? nil : wrong, right: right)
        guard new != old, !right.isEmpty else { return }
        var changed = file
        changed.update(at: index, wrong: new.wrong, right: new.right)
        commit(changed, action: L10n.t("vocabulary.undo.edit"))
    }

    func add(wrong: String, right: String) {
        let wrong = wrong.trimmingCharacters(in: .whitespaces)
        let right = right.trimmingCharacters(in: .whitespaces)
        guard !right.isEmpty else { return }
        var changed = file
        changed.append([Vocabulary.Entry(wrong: wrong.isEmpty ? nil : wrong, right: right)])
        commit(changed, action: L10n.t("vocabulary.undo.add"))
    }

    /// Fügt Zeilen aus der Zwischenablage an, etwa die Liste einer KI. Rückgabe: wie viele.
    @discardableResult
    func paste(_ text: String) -> Int {
        let entries = VocabularyFile.entries(fromPasted: text)
        guard !entries.isEmpty else { return 0 }
        var changed = file
        changed.append(entries)
        commit(changed, action: L10n.t("vocabulary.undo.add"))
        return entries.count
    }

    func remove(lineIDs: Set<UUID>) {
        let indices = Set(file.lines.indices.filter { lineIDs.contains(file.lines[$0].id) && file.lines[$0].entry != nil })
        guard !indices.isEmpty else { return }
        var changed = file
        changed.remove(at: indices)
        commit(changed, action: L10n.t("vocabulary.undo.remove"))
    }

    func keepSessionEntry(at index: Int) {
        guard !isUnreadable else { return }
        store.keepSessionEntry(at: index)
    }

    func removeSessionEntry(at index: Int) {
        store.removeSessionEntry(at: index)
    }

    private func commit(_ changed: VocabularyFile, action: String) {
        guard !isUnreadable else { return }
        let previous = file
        file = changed
        store.write(changed)
        loadedDate = store.modificationDate
        undoManager?.registerUndo(withTarget: self) { editor in
            editor.commit(previous, action: action)
        }
        undoManager?.setActionName(action)
    }
}

private struct VocabularyRow: Identifiable {
    let id: UUID
    let index: Int
    let wrong: String
    let right: String
    let isDuplicate: Bool
}

private struct VocabularyView: View {
    @ObservedObject var editor: VocabularyEditor
    let onReveal: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.undoManager) private var undoManager
    @State private var query = ""
    @State private var selection = Set<UUID>()
    @State private var isAdding = false

    private var rows: [VocabularyRow] {
        let duplicates = editor.file.duplicateWrongs
        let all = editor.file.entries.map { index, entry in
            VocabularyRow(id: editor.file.lines[index].id, index: index, wrong: entry.wrong ?? "", right: entry.right,
                          isDuplicate: entry.wrong.map { duplicates.contains($0.lowercased()) } ?? false)
        }
        let search = query.trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty else { return all }
        return all.filter { $0.wrong.localizedCaseInsensitiveContains(search) || $0.right.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if editor.isUnreadable {
                ContentUnavailableView(L10n.t("vocabulary.unreadable.title"), systemImage: "exclamationmark.triangle",
                                       description: Text(L10n.t("vocabulary.unreadable.text")))
            } else if editor.file.entries.isEmpty && editor.sessionEntries.isEmpty {
                ContentUnavailableView(L10n.t("vocabulary.empty.title"), systemImage: "character.book.closed",
                                       description: Text(L10n.t("vocabulary.empty.text")))
            } else {
                table
            }
            if !editor.sessionEntries.isEmpty {
                Divider()
                sessionList
            }
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear { editor.undoManager = undoManager }
        .onChange(of: undoManager) { editor.undoManager = undoManager }
        .sheet(isPresented: $isAdding) {
            AddEntrySheet { wrong, right in editor.add(wrong: wrong, right: right) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("vocabulary.explanation"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.t("vocabulary.search"), text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
        }
        .padding(14)
    }

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn(L10n.t("vocabulary.heard")) { row in
                EntryField(value: row.wrong, prompt: L10n.t("vocabulary.onlyKnow"), isRequired: false) { text in
                    editor.update(at: row.index, wrong: text, right: row.right)
                }
            }
            TableColumn("") { row in
                Image(systemName: row.isDuplicate ? "exclamationmark.triangle.fill" : "arrow.right")
                    .foregroundStyle(row.isDuplicate ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
                    .help(row.isDuplicate ? L10n.t("vocabulary.duplicate") : "")
            }
            .width(22)
            TableColumn(L10n.t("vocabulary.written")) { row in
                EntryField(value: row.right, prompt: "", isRequired: true) { text in
                    editor.update(at: row.index, wrong: row.wrong, right: text)
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .onDeleteCommand { removeSelection() }
        .onPasteCommand(of: [.plainText]) { _ in
            if let text = NSPasteboard.general.string(forType: .string) { editor.paste(text) }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("vocabulary.session"))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(editor.sessionEntries.enumerated()), id: \.offset) { index, entry in
                HStack {
                    Text(entry.wrong.map { "\($0)  →  \(entry.right)" } ?? entry.right)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.t("vocabulary.keep")) { editor.keepSessionEntry(at: index) }
                        .controlSize(.small)
                    Button { editor.removeSessionEntry(at: index) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help(L10n.t("vocabulary.forget"))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button { isAdding = true } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
                .help(L10n.t("vocabulary.add"))
            Divider().frame(height: 14)
            Button { removeSelection() } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
                .disabled(selection.isEmpty)
                .help(L10n.t("vocabulary.remove"))
            Text(L10n.t("vocabulary.count", editor.file.entries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            Spacer()
            Button(L10n.t("vocabulary.reveal"), action: onReveal)
                .controlSize(.small)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func removeSelection() {
        editor.remove(lineIDs: selection)
        selection.removeAll()
    }
}

/// Ein Feld in der Tabelle. Gespeichert wird beim Drücken von Return oder beim Verlassen des Felds, nicht bei
/// jedem Buchstaben, sonst gäbe es für ein Wort zehn Schritte zum Rückgängigmachen.
private struct EntryField: View {
    let value: String
    let prompt: String
    /// „Wad schreibt“ darf nicht leer werden, „Wad hört“ schon: Dann ist es ein Begriff, den Wad nur kennen soll.
    let isRequired: Bool
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $draft, prompt: Text(prompt))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onAppear { draft = value }
            .onChange(of: value) { draft = value }
            .onSubmit(commitIfValid)
            .onChange(of: isFocused) { if !isFocused { commitIfValid() } }
    }

    private func commitIfValid() {
        if isRequired && draft.trimmingCharacters(in: .whitespaces).isEmpty {
            draft = value        // leer gelassen: Es bleibt beim alten Wort
        } else {
            commit(draft)
        }
    }
}

/// Das kleine Blatt hinter „+“: zwei Felder und „Hinzufügen“.
private struct AddEntrySheet: View {
    let add: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var wrong = ""
    @State private var right = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("vocabulary.add.title")).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.t("vocabulary.heard")).gridColumnAlignment(.trailing)
                    TextField("", text: $wrong, prompt: Text(L10n.t("vocabulary.onlyKnow")))
                        .focused($focused)
                }
                GridRow {
                    Text(L10n.t("vocabulary.written"))
                    TextField("", text: $right)
                }
            }
            .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(L10n.t("common.cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("vocabulary.add.confirm")) {
                    add(wrong, right)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(right.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { focused = true }
    }
}
