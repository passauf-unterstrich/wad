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
}
