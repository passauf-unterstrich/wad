// PreviewPanelTests.swift
// Prüft den Zettel im Vorschau-Fenster: Wo Diktiertes landet, wenn man währenddessen selbst schreibt,
// dass der graue Teil unantastbar ist und Wörter nicht aneinanderkleben.

import XCTest

final class PreviewPanelTests: XCTestCase {
    private var page: PageTextView!

    override func setUp() {
        page = PageTextView()
    }

    /// Tippt wie der Nutzer: über die Prüfung des Textfelds, mit Meldung danach.
    private func type(_ text: String, at location: Int) {
        let range = NSRange(location: location, length: 0)
        guard page.shouldChangeText(in: range, replacementString: text) else { return }
        page.textStorage?.replaceCharacters(in: range, with: text)
        page.didChangeText()
    }

    func testChunksFollowEachOtherWithSpaces() {
        page.beginDictation(atCursor: false)
        page.appendFinal("Hallo")
        page.appendFinal(" Welt.")
        XCTAssertEqual(page.pageText, "Hallo Welt.")
    }

    func testDraftIsNotPartOfThePage() {
        page.beginDictation(atCursor: false)
        page.appendFinal("Hallo")
        page.setDraft("vorläufig")
        XCTAssertEqual(page.pageText, "Hallo")
        XCTAssertEqual(page.string, "Hallo vorläufig")
        page.appendFinal("fertig")
        XCTAssertEqual(page.string, "Hallo fertig", "Ein fertiges Stück löst den Entwurf ab")
    }

    func testEditBeforeTheDictationMovesItAlong() {
        page.beginDictation(atCursor: false)
        page.appendFinal("eins")
        page.setDraft("zwei")
        type("null ", at: 0)
        page.appendFinal("zwei")
        XCTAssertEqual(page.pageText, "null eins zwei", "Diktiertes kommt weiter hinter das eigene Stück, nicht an den Cursor")
    }

    func testDraftCannotBeEdited() {
        page.beginDictation(atCursor: false)
        page.appendFinal("eins")
        page.setDraft("zwei")
        type("x", at: 6)
        XCTAssertEqual(page.string, "eins zwei", "Mitten im grauen Teil wird nichts geändert")
    }

    func testNewDictationGoesToTheCursor() {
        page.beginDictation(atCursor: false)
        page.appendFinal("Anfang Ende")
        page.setSelectedRange(NSRange(location: 6, length: 0))
        page.beginDictation(atCursor: true)
        page.appendFinal("Mitte")
        XCTAssertEqual(page.pageText, "Anfang Mitte Ende")
    }

    func testNewDictationWithoutCursorGoesToTheEnd() {
        page.beginDictation(atCursor: false)
        page.appendFinal("Erster Satz.")
        page.setSelectedRange(NSRange(location: 0, length: 0))
        page.beginDictation(atCursor: false)
        page.appendFinal("Zweiter Satz.")
        XCTAssertEqual(page.pageText, "Erster Satz. Zweiter Satz.")
    }

    func testResetStartsAnEmptyPage() {
        page.beginDictation(atCursor: false)
        page.appendFinal("Text")
        page.setDraft("mehr")
        page.reset()
        XCTAssertEqual(page.string, "")
        page.beginDictation(atCursor: false)
        page.appendFinal("Neu")
        XCTAssertEqual(page.pageText, "Neu")
    }

    /// Wer bei jeder Änderung den Text liest (wie das Fenster), sieht nie einen halb fertigen Stand.
    /// Früher stürzte Wad hier ab, wenn ein fertiges Stück einen längeren Entwurf ablöste.
    func testPageTextIsConsistentOnEveryChange() {
        var seen: [String] = []
        page.onChange = { [unowned self] in seen.append(page.pageText) }
        page.beginDictation(atCursor: false)
        page.setDraft("ein ziemlich langer vorläufiger Satz")
        page.appendFinal("Kurz.")
        page.setDraft("noch was")
        page.setDraft("")
        page.reset()
        XCTAssertEqual(seen, ["", "", "Kurz.", "Kurz.", "Kurz.", ""])
    }

    /// Eine Markierung über die Schreibstelle hinweg löschen: Danach geht es dahinter weiter, nie außerhalb des Textes.
    func testDeletingAcrossTheDictationPositionKeepsItInside() {
        page.beginDictation(atCursor: false)
        page.appendFinal("Anfang Ende")
        page.setSelectedRange(NSRange(location: 6, length: 0))
        page.beginDictation(atCursor: true)
        let range = NSRange(location: 3, length: 8)
        XCTAssertTrue(page.shouldChangeText(in: range, replacementString: ""))
        page.textStorage?.replaceCharacters(in: range, with: "")
        page.didChangeText()
        page.setDraft("weiter")
        page.appendFinal("weiter")
        XCTAssertEqual(page.pageText, "Anf weiter")
    }
}
