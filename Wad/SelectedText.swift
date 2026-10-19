// SelectedText.swift
// Liest den gerade markierten Text der vorderen App über die Bedienungshilfen, ohne die
// Zwischenablage zu benutzen. Nicht jede App gibt ihn heraus; dann bleibt das Feld einfach leer.

import ApplicationServices

enum SelectedText {
    static func current() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
