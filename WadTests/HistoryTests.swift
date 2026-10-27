// HistoryTests.swift
// Prüft beide Verläufe: höchstens 20 Einträge, neuester oben, keine Passwörter, sofortiges Löschen.

import XCTest

final class HistoryTests: XCTestCase {
    func testKeepsOnlyTheNewestTwenty() {
        var history = History()
        for i in 1...25 { history.add("Text \(i)") }
        XCTAssertEqual(history.entries.count, 20)
        XCTAssertEqual(history.entries.first, "Text 25")
        XCTAssertEqual(history.entries.last, "Text 6")
    }

    func testDuplicateMovesToTop() {
        var history = History()
        history.add("A")
        history.add("B")
        history.add("A")
        XCTAssertEqual(history.entries, ["A", "B"])
    }

    func testClearEmptiesImmediately() {
        var history = History()
        history.add("A")
        history.clear()
        XCTAssertEqual(history.entries, [])
    }

    // MARK: Zwischenablage

    private var pasteboard: NSPasteboard!
    private var watcher: ClipboardWatcher!
    private var copied: [String] = []

    override func setUp() {
        pasteboard = NSPasteboard.withUniqueName()
        watcher = ClipboardWatcher(pasteboard: pasteboard)
        copied = []
        watcher.onCopy = { [unowned self] in copied.append($0) }
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    func testRecordsCopiedText() {
        pasteboard.clearContents()
        pasteboard.setString("kopiert", forType: .string)
        watcher.check()
        watcher.check()
        XCTAssertEqual(copied, ["kopiert"], "Jede Kopie wird genau einmal gemeldet")
    }

    func testIgnoresPasswordsAndTransientContent() {
        for marker in ClipboardWatcher.ignoredTypes {
            let item = NSPasteboardItem()
            item.setString("geheim", forType: .string)
            item.setData(Data(), forType: marker)
            pasteboard.clearContents()
            pasteboard.writeObjects([item])
            watcher.check()
        }
        XCTAssertEqual(copied, [])
    }

    func testIgnoresImagesAndEmptyText() {
        pasteboard.clearContents()
        pasteboard.setData(Data([0x89, 0x50]), forType: .png)
        watcher.check()
        pasteboard.clearContents()
        pasteboard.setString("   ", forType: .string)
        watcher.check()
        XCTAssertEqual(copied, [])
    }

    func testReplaceSwapsTheEarlierVersion() {
        var history = History()
        history.add("Zettel")
        history.add("Anderes")
        history.replace("Zettel", with: "Zettel, korrigiert")
        XCTAssertEqual(history.entries, ["Zettel, korrigiert", "Anderes"])
    }
}
