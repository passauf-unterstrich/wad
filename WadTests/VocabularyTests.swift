// VocabularyTests.swift
// Prüft die Vokabelliste: Lesen der Datei, Ersetzen nur ganzer Wörter, Hinweis fürs Modell.

import XCTest

final class VocabularyTests: XCTestCase {
    func testReadsTermsCorrectionsAndSkipsComments() {
        let vocabulary = Vocabulary(text: """
        # Kommentar
        Mise en place

        Watt -> Wad
        kaputt ->
        """)
        XCTAssertEqual(vocabulary.entries, [
            .init(wrong: nil, right: "Mise en place"),
            .init(wrong: "Watt", right: "Wad"),
        ])
    }

    func testReplacesWholeWordsRegardlessOfCase() {
        let vocabulary = Vocabulary(text: "Watt -> Wad\nOskar -> Oscar")
        XCTAssertEqual(vocabulary.apply(to: "Ich teste watt, und Oskar hilft."), "Ich teste Wad, und Oscar hilft.")
    }

    func testLeavesWordsThatOnlyContainTheMistake() {
        let vocabulary = Vocabulary(text: "Watt -> Wad")
        XCTAssertEqual(vocabulary.apply(to: "Wattestäbchen und Kilowatt"), "Wattestäbchen und Kilowatt")
    }

    func testReplacesEveryOccurrence() {
        let vocabulary = Vocabulary(text: "Watt -> Wad")
        XCTAssertEqual(vocabulary.apply(to: "Watt Watt"), "Wad Wad")
    }

    func testHintListsCorrectSpellingsWithinLimit() {
        XCTAssertNil(Vocabulary().hint)
        XCTAssertEqual(Vocabulary(text: "Watt -> Wad\nBeurre blanc").hint, "Wad, Beurre blanc.")

        let many = Vocabulary(text: (1...60).map { "Begriff\($0)" }.joined(separator: "\n"))
        XCTAssertEqual(many.hint?.components(separatedBy: ", ").count, Vocabulary.hintLimit)
    }

    func testPermanentEntryIsWrittenToFileAndSessionEntryIsNot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = VocabularyStore(directory: directory)
        store.add(.init(wrong: "Oskar", right: "Oscar"), permanently: true)
        store.add(.init(wrong: "Watt", right: "Wad"), permanently: false)
        XCTAssertEqual(store.vocabulary.apply(to: "Oskar und Watt"), "Oscar und Wad")

        let fresh = VocabularyStore(directory: directory)
        XCTAssertEqual(fresh.vocabulary.apply(to: "Oskar und Watt"), "Oscar und Watt", "Sitzungs-Einträge überleben keinen Neustart")
    }

    // MARK: Fenster „Vokabeln“: dieselbe Datei, nichts geht verloren

    /// Eine Liste, wie sie über Wochen von Hand gewachsen ist: Kommentare, Leerzeilen, Windows-Zeilenenden,
    /// Einrückung, eine kaputte Zeile.
    private let handmade = "# Meine Liste\r\nWatt -> Wad\r\n\n  Mise en place  \nkaputt ->\nOskar->Oscar\n# Ende\n"

    func testUntouchedFileComesBackCharacterForCharacter() {
        XCTAssertEqual(VocabularyFile(text: handmade).text, handmade)
        XCTAssertEqual(VocabularyFile(text: "").text, "")
    }

    func testWindowSeesExactlyTheEntriesDictationUses() {
        let file = VocabularyFile(text: handmade)
        XCTAssertEqual(file.entries.map(\.entry), Vocabulary(text: handmade).entries)
        XCTAssertEqual(file.entries.count, 3)
    }

    func testEditingOneEntryLeavesEverythingElseAlone() {
        var file = VocabularyFile(text: handmade)
        let oskar = file.entries.first { $0.entry.right == "Oscar" }!.index
        file.update(at: oskar, wrong: "Oskar", right: "Oscar Wilde")
        XCTAssertEqual(file.text, handmade.replacingOccurrences(of: "Oskar->Oscar", with: "Oskar -> Oscar Wilde"))
        XCTAssertEqual(Vocabulary(text: file.text).apply(to: "Oskar und Watt"), "Oscar Wilde und Wad")
    }

    func testPureTermAndCleanedArrow() {
        var file = VocabularyFile(text: "Watt -> Wad")
        file.update(at: 0, wrong: nil, right: "Wad")
        XCTAssertEqual(file.text, "Wad")
        file.update(at: 0, wrong: "A -> B", right: "C")
        XCTAssertEqual(Vocabulary(text: file.text).entries, [.init(wrong: "A → B", right: "C")], "„->“ in einem Feld zerlegt nie die Zeile")
    }

    func testAppendAndRemove() {
        var file = VocabularyFile(text: "Watt -> Wad\n\n")
        file.append([.init(wrong: nil, right: "Beurre blanc")])
        XCTAssertEqual(file.text, "Watt -> Wad\nBeurre blanc", "keine Leerzeilen vor dem Neuen")
        file.remove(at: [0])
        XCTAssertEqual(file.text, "Beurre blanc")
    }

    func testUnfinishedEntryIsNotWritten() {
        var file = VocabularyFile(text: "Watt -> Wad")
        file.append([.init(wrong: "Oskar", right: "  ")])
        XCTAssertEqual(file.text, "Watt -> Wad")
    }

    func testDuplicatesAreFound() {
        XCTAssertEqual(VocabularyFile(text: "Watt -> Wad\nwatt -> What\nOskar -> Oscar").duplicateWrongs, ["watt"])
    }

    func testPastedListFromAnAI() {
        let pasted = "Hier ist deine Liste:\n- Watt -> Wad\n• Mise en place\n\n# Kommentar\n"
        XCTAssertEqual(VocabularyFile.entries(fromPasted: pasted), [
            .init(wrong: "Watt", right: "Wad"),
            .init(wrong: nil, right: "Mise en place"),
        ])
    }

    func testStoreWritesBacksUpOnceAndNeverTouchesAnUnreadableFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = VocabularyStore(directory: directory)
        try handmade.write(to: store.fileURL, atomically: true, encoding: .utf8)

        store.backUpOnce()
        var file = try XCTUnwrap(store.file)
        file.append([.init(wrong: "Wadd", right: "Wad")])
        store.write(file)
        store.backUpOnce()
        XCTAssertEqual(try String(contentsOf: store.backupURL, encoding: .utf8), handmade, "Die Sicherung bleibt die alte Liste")
        XCTAssertEqual(store.vocabulary.apply(to: "Wadd"), "Wad")

        let utf16 = Data([0xFF, 0xFE, 0x57, 0x00, 0x00, 0xD8])
        try utf16.write(to: store.fileURL)
        XCTAssertNil(store.file, "Nicht lesbar heißt: nicht bearbeitbar, also auch nie überschrieben")
    }

    func testKeepingASessionEntryMakesItPermanent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VocabularyStore(directory: directory)
        store.add(.init(wrong: "Watt", right: "Wad"), permanently: false)
        store.keepSessionEntry(at: 0)
        XCTAssertTrue(store.sessionEntries.isEmpty)
        XCTAssertEqual(VocabularyStore(directory: directory).vocabulary.apply(to: "Watt"), "Wad")
    }
}

