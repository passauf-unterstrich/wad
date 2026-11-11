// SelectedText.swift
// Holt den gerade markierten Text der vorderen App für das Korrektur-Fenster.
// Erster Weg: direkt über die Bedienungshilfen, ohne die Zwischenablage zu berühren.
// Viele Apps (Browser, Electron-Apps wie Claude oder WhatsApp) geben ihn so aber nicht heraus.
// Dann kopiert Wad die Markierung kurz mit Cmd+C und stellt die Zwischenablage sofort wieder her.

import AppKit

enum SelectedText {
    /// So lange wartet Wad höchstens, bis die vordere App die Kopie abgelegt hat.
    static let copyTimeout: TimeInterval = 0.3

    static func current(pasteboard: NSPasteboard = .general) -> String? {
        let text = fromAccessibility() ?? byCopying(from: pasteboard)
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Was vor dem Cursor der vorderen App steht.
    enum CursorContext: Equatable {
        /// Der Cursor steht ganz am Anfang des Felds.
        case atStart
        case character(Character)
        /// Die App verrät es nicht (viele Browser- und Electron-Apps wie Claude oder WhatsApp).
        case unknown
    }

    /// Das Zeichen direkt vor dem Cursor, damit ein neues Diktat nicht an den Satz davor klebt („Gut.Dann“).
    /// Liest über die Bedienungshilfen nur dieses eine Zeichen, nie mehr, und merkt es sich nicht.
    static func contextBeforeCursor() -> CursorContext {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
        let element = focused as! AXUIElement
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return .unknown }
        var selection = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection) else { return .unknown }
        guard selection.location > 0 else { return .atStart }
        // Zwei Stellen, weil manche Zeichen (Emoji, seltene chinesische Zeichen) zwei belegen.
        let length = min(selection.location, 2)
        var wanted = CFRange(location: selection.location - length, length: length)
        guard let wantedValue = AXValueCreate(.cfRange, &wanted) else { return .unknown }
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                         wantedValue, &text) == .success,
              let last = (text as? String)?.last else { return .unknown }
        return .character(last)
    }

    private static func fromAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String, !text.isEmpty else { return nil }
        return text
    }

    /// Läuft bewusst auf dem Hauptthread und wartet kurz: So kann in dieser Zeit nichts anderes
    /// in Wad die Zwischenablage lesen, auch nicht der Zwischenablage-Verlauf.
    private static func byCopying(from pasteboard: NSPasteboard) -> String? {
        let saved = TextInserter.snapshot(of: pasteboard)
        let before = pasteboard.changeCount
        TextInserter.postCommand(key: 8)   // Taste C (Apple: kVK_ANSI_C)

        let deadline = Date().addingTimeInterval(copyTimeout)
        while pasteboard.changeCount == before, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
        return text
    }
}
