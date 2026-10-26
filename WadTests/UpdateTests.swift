// UpdateTests.swift
// Prüft die Regeln der Update-Prüfung ohne Netzwerk: Versionsvergleich, wann das Fenster kommt,
// was Überspringen bewirkt und wann „Was ist neu“ erscheint.

import XCTest

final class UpdateTests: XCTestCase {
    private func v(_ text: String) -> AppVersion { AppVersion(text)! }

    // MARK: Versionen

    func testComparesPartByPartAsNumbers() {
        XCTAssertLessThan(v("1.0.2"), v("1.1.0"))
        XCTAssertLessThan(v("1.9.0"), v("1.10.0"))
        XCTAssertLessThan(v("1.1.0"), v("2.0"))
        XCTAssertFalse(v("1.1.0") < v("1.1.0"))
    }

    func testLeadingVAndMissingPartsCount() {
        XCTAssertEqual(v("v1.1.0"), v("1.1.0"))
        XCTAssertEqual(v("1.1"), v("1.1.0"))
        XCTAssertEqual(v("v1.2").description, "1.2")
    }

    func testRejectsPreReleasesAndGarbage() {
        XCTAssertNil(AppVersion("1.2.0-beta"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("Wad"))
    }

    // MARK: Hinweis und Überspringen

    func testOffersOnlyNewerVersions() {
        XCTAssertTrue(UpdateRules.isOffered(v("1.1.1"), current: v("1.1.0"), skipped: nil))
        XCTAssertFalse(UpdateRules.isOffered(v("1.1.0"), current: v("1.1.0"), skipped: nil))
        XCTAssertFalse(UpdateRules.isOffered(v("1.0.2"), current: v("1.1.0"), skipped: nil))
    }

    func testWindowComesOncePerVersion() {
        XCTAssertTrue(UpdateRules.announces(v("1.1.1"), current: v("1.1.0"), skipped: nil, announced: nil))
        XCTAssertFalse(UpdateRules.announces(v("1.1.1"), current: v("1.1.0"), skipped: nil, announced: v("1.1.1")))
        XCTAssertTrue(UpdateRules.announces(v("1.1.2"), current: v("1.1.0"), skipped: nil, announced: v("1.1.1")))
    }

    func testSkippedVersionStaysHidden() {
        XCTAssertFalse(UpdateRules.isOffered(v("1.1.1"), current: v("1.1.0"), skipped: v("1.1.1")))
        XCTAssertFalse(UpdateRules.announces(v("1.1.1"), current: v("1.1.0"), skipped: v("1.1.1"), announced: nil))
    }

    func testNewerThanSkippedShowsAgain() {
        XCTAssertTrue(UpdateRules.isOffered(v("1.2.0"), current: v("1.1.0"), skipped: v("1.1.1")))
        XCTAssertTrue(UpdateRules.announces(v("1.2.0"), current: v("1.1.0"), skipped: v("1.1.1"), announced: v("1.1.1")))
    }

    // MARK: Was ist neu

    func testFreshInstallShowsNothing() {
        XCTAssertFalse(UpdateRules.showsWhatsNew(current: v("1.1.0"), lastSeen: nil, hadEarlierVersion: false))
    }

    func testUpdateFromOneZeroShows() {
        XCTAssertTrue(UpdateRules.showsWhatsNew(current: v("1.1.0"), lastSeen: nil, hadEarlierVersion: true))
    }

    func testShowsOnceAfterEachUpdate() {
        XCTAssertTrue(UpdateRules.showsWhatsNew(current: v("1.2.0"), lastSeen: v("1.1.0"), hadEarlierVersion: true))
        XCTAssertFalse(UpdateRules.showsWhatsNew(current: v("1.1.0"), lastSeen: v("1.1.0"), hadEarlierVersion: true))
    }

    // MARK: Standard an, einmaliger Hinweis

    func testCheckingIsOnUnlessSwitchedOff() {
        XCTAssertTrue(UpdateRules.isEnabled(stored: nil), "Ab Werk an")
        XCTAssertFalse(UpdateRules.isEnabled(stored: false))
        XCTAssertTrue(UpdateRules.isEnabled(stored: true))
    }

    func testInfoComesOnceAndNotAfterAnEarlierChoice() {
        XCTAssertTrue(UpdateRules.needsInfo(stored: nil, infoShown: false))
        XCTAssertFalse(UpdateRules.needsInfo(stored: nil, infoShown: true), "Nur einmal")
        XCTAssertFalse(UpdateRules.needsInfo(stored: false, infoShown: false), "Frühere Wahl bleibt")
        XCTAssertFalse(UpdateRules.needsInfo(stored: true, infoShown: false))
    }

    // MARK: Beschreibung von GitHub

    func testNotesBecomePlainText() {
        let notes = "## Neu\r\n* **Schneller** beim [Einfügen](https://example.com)\n<b>Fett</b> und `Code`"
        XCTAssertEqual(UpdateRules.plainText(notes), "Neu\n- Schneller beim Einfügen\nFett und Code")
    }
}
