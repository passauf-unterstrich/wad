// WindowLayoutTests.swift
// Prüft die Rechnung des Fenstermanagers: Hälften, Viertel, Durchschalten, Zentrieren, Bildschirmrand.

import XCTest

final class WindowLayoutTests: XCTestCase {
    /// Ein Bildschirm, dessen nutzbare Fläche wegen der Menüleiste erst bei y = 25 beginnt.
    private let visible = CGRect(x: 0, y: 25, width: 1200, height: 800)
    private let window = CGRect(x: 100, y: 100, width: 400, height: 300)

    private func frame(_ action: WindowAction, step: Int = 0) -> CGRect {
        WindowLayout.frame(for: action, in: visible, current: window, step: step)
    }

    func testMaximizeFillsVisibleArea() {
        XCTAssertEqual(frame(.maximize), visible)
    }

    func testHalves() {
        XCTAssertEqual(frame(.left), CGRect(x: 0, y: 25, width: 600, height: 800))
        XCTAssertEqual(frame(.right), CGRect(x: 600, y: 25, width: 600, height: 800))
        XCTAssertEqual(frame(.top), CGRect(x: 0, y: 25, width: 1200, height: 400))
        XCTAssertEqual(frame(.bottom), CGRect(x: 0, y: 425, width: 1200, height: 400))
    }

    func testRepeatedPressCyclesHalfTwoThirdsThird() {
        XCTAssertEqual(frame(.left, step: 0).width, 600)
        XCTAssertEqual(frame(.left, step: 1).width, 800)
        XCTAssertEqual(frame(.left, step: 2).width, 400)
        XCTAssertEqual(frame(.left, step: 3).width, 600, "Nach ⅓ geht es wieder bei ½ los")
        XCTAssertEqual(frame(.right, step: 1).maxX, visible.maxX, "Rechts bleibt am rechten Rand")
    }

    func testQuartersGoClockwiseFromTopLeft() {
        XCTAssertEqual(frame(.topLeft), CGRect(x: 0, y: 25, width: 600, height: 400))
        XCTAssertEqual(frame(.topRight), CGRect(x: 600, y: 25, width: 600, height: 400))
        XCTAssertEqual(frame(.bottomRight), CGRect(x: 600, y: 425, width: 600, height: 400))
        XCTAssertEqual(frame(.bottomLeft), CGRect(x: 0, y: 425, width: 600, height: 400))
    }

    func testCenterKeepsSize() {
        XCTAssertEqual(frame(.center), CGRect(x: 400, y: 275, width: 400, height: 300))
    }

    func testMinimumSizeIsPushedBackOnScreen() {
        // Die App lässt das Fenster nicht schmaler als 700 werden, gewünscht war die rechte Hälfte.
        let tooWide = CGRect(x: 600, y: 25, width: 700, height: 800)
        XCTAssertEqual(WindowLayout.keepOnScreen(tooWide, in: visible), CGRect(x: 500, y: 25, width: 700, height: 800))
    }
}
