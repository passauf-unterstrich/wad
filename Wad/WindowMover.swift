// WindowMover.swift
// Verschiebt das vordere Fenster der vorderen App über die Bedienungshilfen (SPEC 1.8).
// Merkt sich die letzte Aktion, damit wiederholtes Drücken durch ½, ⅔ und ⅓ schaltet.

import AppKit

final class WindowMover {
    private var last: (action: WindowAction, window: AXUIElement, frame: CGRect, step: Int)?

    func perform(_ action: WindowAction) {
        guard let window = Self.focusedWindow(), Self.canMove(window),
              let current = Self.frame(of: window),
              let visible = Self.visibleFrame(around: current) else { return }

        // Gleiches Kürzel, gleiches Fenster, Fenster seitdem nicht bewegt: nächste Größe.
        var step = 0
        if action.cycles, let last, last.action == action, CFEqual(last.window, window),
           Self.isClose(last.frame, current) {
            step = last.step + 1
        }

        let target = WindowLayout.frame(for: action, in: visible, current: current, step: step)
        Self.set(window, to: target)
        // Hat die App eine Mindestgröße, ist das Fenster größer als gewünscht: zurück auf den Bildschirm.
        if let actual = Self.frame(of: window), actual.size != target.size {
            Self.set(window, to: WindowLayout.keepOnScreen(actual, in: visible))
        }
        last = (action, window, Self.frame(of: window) ?? target, step)
    }

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success else { return nil }
        return (window as! AXUIElement)
    }

    /// Fenster im macOS-Vollbild und Fenster, die sich nicht verschieben lassen, bleiben in Ruhe.
    private static func canMove(_ window: AXUIElement) -> Bool {
        var fullScreen: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreen) == .success,
           (fullScreen as? Bool) == true { return false }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
        return settable.boolValue
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    /// Erst verschieben, dann Größe setzen, dann noch einmal verschieben: So landen auch Fenster
    /// richtig, die beim Größerwerden sonst über den Bildschirmrand hinaus wachsen würden.
    private static func set(_ window: AXUIElement, to frame: CGRect) {
        var position = frame.origin
        var size = frame.size
        let positionValue = AXValueCreate(.cgPoint, &position)!
        let sizeValue = AXValueCreate(.cgSize, &size)!
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    }

    /// Nutzbare Fläche des Bildschirms, auf dem das Fenster gerade am meisten liegt,
    /// umgerechnet in die Koordinaten der Bedienungshilfen (Ursprung oben links).
    private static func visibleFrame(around window: CGRect) -> CGRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        func flipped(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        }
        let screen = NSScreen.screens.max { a, b in
            flipped(a.frame).intersection(window).area < flipped(b.frame).intersection(window).area
        }
        return screen.map { flipped($0.visibleFrame) }
    }

    private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
