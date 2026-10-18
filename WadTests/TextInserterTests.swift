// TextInserterTests.swift
// Prüft, dass Wad die Zwischenablage nach dem Einfügen unverändert zurücklässt (SPEC 2.5).
// Jeder Test nutzt eine eigene, private Zwischenablage, die echte bleibt unberührt.

import XCTest

final class TextInserterTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var seenWhilePasting: String?
    private var inserter: TextInserter!

    override func setUp() {
        pasteboard = NSPasteboard.withUniqueName()
        seenWhilePasting = nil
        inserter = TextInserter(pasteboard: pasteboard, restoreDelay: 0.05) { [unowned self] in
            seenWhilePasting = pasteboard.string(forType: .string)
        }
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    func testPreviousContentIncludingImageIsRestored() {
        let image = Data([0x89, 0x50, 0x4E, 0x47])
        let item = NSPasteboardItem()
        item.setString("vorher", forType: .string)
        item.setData(image, forType: .png)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        inserter.insert("Diktat")
        XCTAssertEqual(seenWhilePasting, "Diktat")
        XCTAssertNotNil(pasteboard.data(forType: TextInserter.transientType), "Diktat ist als vorübergehend markiert")

        waitForRestore()
        XCTAssertEqual(pasteboard.string(forType: .string), "vorher")
        XCTAssertEqual(pasteboard.data(forType: .png), image)
        XCTAssertNil(pasteboard.data(forType: TextInserter.transientType))
    }

    func testWhatUserCopiedMeanwhileIsKept() {
        inserter.insert("Diktat")
        pasteboard.clearContents()
        pasteboard.setString("vom Nutzer", forType: .string)

        waitForRestore()
        XCTAssertEqual(pasteboard.string(forType: .string), "vom Nutzer")
    }

    func testEmptyClipboardStaysEmpty() {
        pasteboard.clearContents()
        inserter.insert("Diktat")

        waitForRestore()
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    private func waitForRestore() {
        let restored = expectation(description: "Zwischenablage wiederhergestellt")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { restored.fulfill() }
        wait(for: [restored], timeout: 1)
    }
}
