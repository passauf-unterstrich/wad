// VocabularyStore.swift
// Hält die Vokabeln: die dauerhafte Liste als Textdatei an einem festen, sichtbaren Ort und
// die Einträge „nur bis zum Neustart“ im Arbeitsspeicher. Die Datei darf man von Hand oder mit
// Hilfe einer KI bearbeiten; Wad liest sie vor jedem Diktat neu, wenn sie sich geändert hat.
// Das Fenster „Vokabeln“ bearbeitet dieselbe Datei, es gibt kein zweites Format.

import Foundation

final class VocabularyStore {
    /// ~/Library/Application Support/Wad/Vokabeln.txt
    let fileURL: URL
    private var permanent = Vocabulary()
    private var session = Vocabulary()
    private var loadedModificationDate: Date?
    /// Die Liste hat sich geändert, durch Wad selbst oder von außen. Für das Fenster „Vokabeln“.
    var onChange: (() -> Void)?

    /// Einmalige Kopie der Liste, wie sie vor dem ersten Start mit Vokabel-Fenster war.
    var backupURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("Vokabeln-Sicherung.txt") }

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wad", isDirectory: true)) {
        fileURL = directory.appendingPathComponent("Vokabeln.txt")
    }

    /// Dauerhafte und Sitzungs-Einträge zusammen, Sitzung zuerst.
    var vocabulary: Vocabulary {
        reloadIfChanged()
        return Vocabulary(entries: session.entries + permanent.entries)
    }

    func add(_ entry: Vocabulary.Entry, permanently: Bool) {
        guard permanently else {
            session.entries.append(entry)
            onChange?()
            return
        }
        createFileIfNeeded()
        let line = entry.wrong.map { "\($0) -> \(entry.right)" } ?? entry.right
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(Data(("\n" + line).utf8))
            try? handle.close()
        }
        reloadIfChanged()
        onChange?()
    }

    /// Die Einträge „nur bis zum Neustart“.
    var sessionEntries: [Vocabulary.Entry] { session.entries }

    /// Ein Eintrag „nur bis zum Neustart“ wird dauerhaft.
    func keepSessionEntry(at index: Int) {
        guard session.entries.indices.contains(index) else { return }
        guard var file = self.file else { return }
        let entry = session.entries.remove(at: index)
        file.append([entry])
        write(file)
    }

    func removeSessionEntry(at index: Int) {
        guard session.entries.indices.contains(index) else { return }
        session.entries.remove(at: index)
        onChange?()
    }

    /// Die Datei Zeile für Zeile, zum Bearbeiten. `nil`, wenn es sie gibt, sie sich aber nicht als Text lesen
    /// lässt: Dann darf das Fenster sie auf keinen Fall überschreiben.
    var file: VocabularyFile? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return VocabularyFile(text: "") }
        return (try? String(contentsOf: fileURL, encoding: .utf8)).map(VocabularyFile.init)
    }

    /// Wann die Datei zuletzt geändert wurde, `nil`, wenn es sie nicht gibt.
    var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    /// Schreibt die bearbeitete Liste. Atomar: Stürzt etwas ab, bleibt die alte Datei ganz.
    func write(_ file: VocabularyFile) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? file.text.write(to: fileURL, atomically: true, encoding: .utf8)
        reloadIfChanged()
        onChange?()
    }

    /// Legt beim ersten Mal eine Sicherungskopie neben die Liste. Eine vorhandene Sicherung bleibt, wie sie ist.
    func backUpOnce() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path), !manager.fileExists(atPath: backupURL.path) else { return }
        try? manager.copyItem(at: fileURL, to: backupURL)
    }

    /// Legt die Datei mit einer kurzen Anleitung an, falls es sie noch nicht gibt.
    func createFileIfNeeded() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Self.template.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func reloadIfChanged() {
        let modified = modificationDate
        guard modified != loadedModificationDate else { return }
        loadedModificationDate = modified
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        permanent = Vocabulary(text: text)
    }

    private static var template: String { L10n.t("vocabulary.template") }
}