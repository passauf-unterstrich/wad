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
