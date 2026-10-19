// VocabularyStore.swift
// Hält die Vokabeln: die dauerhafte Liste als Textdatei an einem festen, sichtbaren Ort und
// die Einträge „nur bis zum Neustart“ im Arbeitsspeicher. Die Datei darf man von Hand oder mit
// Hilfe einer KI bearbeiten; Wad liest sie vor jedem Diktat neu, wenn sie sich geändert hat.

import Foundation

final class VocabularyStore {
    /// ~/Library/Application Support/Wad/Vokabeln.txt
    let fileURL: URL
    private var permanent = Vocabulary()
    private var session = Vocabulary()
    private var loadedModificationDate: Date?

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
    }

    /// Legt die Datei mit einer kurzen Anleitung an, falls es sie noch nicht gibt.
    func createFileIfNeeded() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Self.template.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func reloadIfChanged() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modified = attributes?[.modificationDate] as? Date
        guard modified != loadedModificationDate else { return }
        loadedModificationDate = modified
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        permanent = Vocabulary(text: text)
    }

    private static let template = """
    # Wads Vokabelliste. Eine Zeile pro Eintrag, Zeilen mit # werden übergangen.
    #
    # Nur ein Begriff: Wad soll ihn kennen und genau so schreiben.
    #   Mise en place
    #
    # Falsch -> Richtig: Wad ersetzt das Falsche immer durch das Richtige.
    #   Watt -> Wad
    """
}